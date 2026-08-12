defmodule Tunneld.Machines.SSH.Session do
  @moduledoc """
  GenServer owning a single interactive SSH session to a managed machine.

  Uses Erlang's built-in `:ssh` / `:ssh_connection` modules (OTP ships them).
  Each session allocates a PTY, starts a shell, and streams data bidirectionally
  between the browser (via Phoenix channel) and the remote machine.

  Key design points:
  - `:ssh.connect/4` to `Overlay.address_for(machine)` (NOT the raw address -
    remote machines are reached over WireGuard).
  - Authenticates via `user_dir` containing the machine's private key as
    `id_ed25519`. This is the only reliable method for OpenSSH-format keys
    with Erlang's :ssh client.
  - `silently_accept_hosts: true` because managed machines are ephemeral VMs
    whose host keys rotate on reprovision; the security model trusts our own
    SSH key installed on the target, not TOFU host-key checking.
  - The SSH connection AND the temp user_dir are cleaned up when this GenServer
    dies, preventing both leaked connections and leaked key copies.

  In mock mode, no real SSH connection is made; a fake shell transcript is
  emitted instead.
  """
  use GenServer
  require Logger

  alias Tunneld.Machines.SSH
  alias Tunneld.Overlay

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @connect_timeout 15_000
  @default_cols 80
  @default_rows 24

  defstruct [
    :machine_id,
    :connection,
    :channel_id,
    :subscriber,
    :machine,
    :cols,
    :rows,
    :user_dir
  ]

  # ───────────────────────────────────────────────────────────────────────────
  # Public API
  # ───────────────────────────────────────────────────────────────────────────

  @doc """
  Start a linked SSH session to a managed machine.

  Options:
  - `:machine_id` (required) - the machine UUID
  - `:subscriber` (required) - pid to send `{:ssh_data, binary}` messages to
  - `:cols` - terminal columns (default 80)
  - `:rows` - terminal rows (default 24)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Send keystrokes (binary data) to the remote shell.
  """
  def send_data(pid, data) when is_binary(data) do
    GenServer.cast(pid, {:send_data, data})
  end

  @doc """
  Notify the session of a terminal resize.
  """
  def resize(pid, cols, rows) when is_integer(cols) and is_integer(rows) do
    GenServer.cast(pid, {:resize, cols, rows})
  end

  @doc """
  Stop the session gracefully.
  """
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  @doc """
  Returns true if running in mock mode.
  """
  def mock?, do: @mock

  # ───────────────────────────────────────────────────────────────────────────
  # GenServer callbacks
  # ───────────────────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    with {:ok, machine_id} <- Keyword.fetch(opts, :machine_id),
         {:ok, subscriber} <- Keyword.fetch(opts, :subscriber) do
      cols = Keyword.get(opts, :cols, @default_cols)
      rows = Keyword.get(opts, :rows, @default_rows)

      # Monitor the subscriber so we terminate if the channel dies
      Process.monitor(subscriber)

      state = %__MODULE__{
        machine_id: machine_id,
        subscriber: subscriber,
        cols: cols,
        rows: rows
      }

      # Connect asynchronously so init doesn't block
      send(self(), :connect)
      {:ok, state}
    else
      :error -> {:stop, :missing_required_option}
    end
  end

  @impl true
  def handle_info(:connect, state) do
    if @mock do
      handle_mock_connect(state)
    else
      handle_real_connect(state)
    end
  end

  # Handle SSH data from the remote
  @impl true
  def handle_info(
        {:ssh_cm, conn, {:data, channel_id, _type, data}},
        %{connection: conn, channel_id: channel_id} = state
      ) do
    send(state.subscriber, {:ssh_data, data})
    {:noreply, state}
  end

  # Channel closed by remote
  @impl true
  def handle_info(
        {:ssh_cm, conn, {:eof, channel_id}},
        %{connection: conn, channel_id: channel_id} = state
      ) do
    send(state.subscriber, {:ssh_closed, "Remote closed the connection"})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(
        {:ssh_cm, conn, {:exit_status, channel_id, _status}},
        %{connection: conn, channel_id: channel_id} = state
      ) do
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:ssh_cm, conn, {:closed, channel_id}},
        %{connection: conn, channel_id: channel_id} = state
      ) do
    send(state.subscriber, {:ssh_closed, "Channel closed"})
    {:stop, :normal, state}
  end

  # Subscriber (channel) died - terminate
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{subscriber: pid} = state) do
    {:stop, :normal, state}
  end

  # Mock mode: simulate shell output
  @impl true
  def handle_info(:mock_banner, state) do
    banner = """
    \r\nWelcome to mock shell for #{state.machine_id}\r
    Linux tunneld-mock 6.1.0 #1 SMP PREEMPT aarch64 GNU/Linux\r
    \r
    Last login: #{DateTime.utc_now() |> DateTime.to_string()}\r
    mock@tunneld:~$ \
    """

    send(state.subscriber, {:ssh_data, banner})
    {:noreply, state}
  end

  # Catch-all for other SSH messages
  @impl true
  def handle_info({:ssh_cm, _conn, msg}, state) do
    Logger.debug("SSH session ignoring message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send_data, data}, state) do
    if @mock do
      handle_mock_input(data, state)
    else
      handle_real_input(data, state)
    end
  end

  @impl true
  def handle_cast({:resize, cols, rows}, %{connection: conn, channel_id: channel_id} = state)
      when not is_nil(conn) do
    # Send window change (resize) to the PTY
    :ssh_connection.window_change(conn, channel_id, cols, rows, 0, 0)
    {:noreply, %{state | cols: cols, rows: rows}}
  end

  def handle_cast({:resize, cols, rows}, state) do
    {:noreply, %{state | cols: cols, rows: rows}}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up the SSH connection
    if state.connection do
      :ssh.close(state.connection)
    end

    # CRITICAL: Remove the temp user_dir to avoid leaking private key copies
    if state.user_dir do
      cleanup_user_dir(state.user_dir)
    end

    :ok
  end

  # ───────────────────────────────────────────────────────────────────────────
  # Real SSH connection
  # ───────────────────────────────────────────────────────────────────────────

  defp handle_real_connect(state) do
    case do_connect(state) do
      {:ok, new_state} ->
        send(state.subscriber, {:ssh_connected})
        {:noreply, new_state}

      {:error, reason} ->
        send(state.subscriber, {:ssh_error, format_error(reason)})
        {:stop, :normal, state}
    end
  end

  defp handle_real_input(data, %{connection: conn, channel_id: channel_id} = state)
       when not is_nil(conn) do
    :ssh_connection.send(conn, channel_id, data)
    {:noreply, state}
  end

  defp handle_real_input(_data, state) do
    # Not connected yet, drop the data
    {:noreply, state}
  end

  defp do_connect(state) do
    case Tunneld.Machines.get(state.machine_id) do
      {:ok, machine} ->
        # Use overlay address (WireGuard) for remote machines
        host = Overlay.address_for(machine) |> String.to_charlist()
        port = (machine["ssh_port"] || 22) |> ensure_integer()
        user = (machine["ssh_user"] || "root") |> String.to_charlist()

        key_path = SSH.private_key_path(state.machine_id)

        unless File.exists?(key_path) do
          throw({:error, :no_key})
        end

        # Create a temp user_dir with the private key as id_ed25519
        case setup_user_dir(key_path) do
          {:ok, user_dir} ->
            connect_opts = [
              user: user,
              user_dir: String.to_charlist(user_dir),
              # silently_accept_hosts: true is intentional here. Managed machines
              # are ephemeral VMs whose host keys rotate on reprovision. Our
              # security model trusts the SSH key we installed on enrollment,
              # not TOFU host-key verification. The gateway is the trust anchor.
              silently_accept_hosts: true,
              auth_methods: ~c"publickey",
              user_interaction: false,
              connect_timeout: @connect_timeout
            ]

            case :ssh.connect(host, port, connect_opts, @connect_timeout) do
              {:ok, conn} ->
                case open_shell(conn, state.cols, state.rows) do
                  {:ok, channel_id} ->
                    {:ok,
                     %{
                       state
                       | connection: conn,
                         channel_id: channel_id,
                         machine: machine,
                         user_dir: user_dir
                     }}

                  {:error, reason} ->
                    :ssh.close(conn)
                    cleanup_user_dir(user_dir)
                    {:error, reason}
                end

              {:error, reason} ->
                cleanup_user_dir(user_dir)
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} ->
        {:error, :machine_not_found}
    end
  catch
    {:error, reason} -> {:error, reason}
  end

  # Create a temp directory with the private key as id_ed25519 (mode 0600)
  # This is required because Erlang's :ssh client only reliably reads keys
  # from user_dir in OpenSSH format.
  defp setup_user_dir(key_path) do
    # Use a unique directory name to avoid collisions
    nonce = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    user_dir = Path.join(System.tmp_dir!(), "tunneld_ssh_#{nonce}")

    try do
      File.mkdir_p!(user_dir)
      File.chmod!(user_dir, 0o700)

      # Copy the private key as id_ed25519
      dest = Path.join(user_dir, "id_ed25519")
      File.cp!(key_path, dest)
      File.chmod!(dest, 0o600)

      {:ok, user_dir}
    rescue
      e -> {:error, {:user_dir_setup_failed, Exception.message(e)}}
    end
  end

  # Remove the temp user_dir and its contents
  defp cleanup_user_dir(user_dir) when is_binary(user_dir) do
    # Securely remove the key file first, then the directory
    key_file = Path.join(user_dir, "id_ed25519")

    if File.exists?(key_file) do
      File.rm(key_file)
    end

    if File.exists?(user_dir) do
      File.rmdir(user_dir)
    end
  rescue
    _ -> :ok
  end

  defp cleanup_user_dir(_), do: :ok

  defp open_shell(conn, cols, rows) do
    case :ssh_connection.session_channel(conn, @connect_timeout) do
      {:ok, channel_id} ->
        # Allocate a PTY with the given dimensions
        case :ssh_connection.ptty_alloc(conn, channel_id, [
               {:term, ~c"xterm-256color"},
               {:width, cols},
               {:height, rows}
             ]) do
          :success ->
            # Start the shell
            case :ssh_connection.shell(conn, channel_id) do
              :ok ->
                {:ok, channel_id}

              error ->
                {:error, {:shell_failed, error}}
            end

          :failure ->
            {:error, :pty_alloc_failed}

          {:error, reason} ->
            {:error, {:pty_alloc_error, reason}}
        end

      {:error, reason} ->
        {:error, {:channel_open_failed, reason}}
    end
  end

  # ───────────────────────────────────────────────────────────────────────────
  # Mock mode
  # ───────────────────────────────────────────────────────────────────────────

  defp handle_mock_connect(state) do
    # In mock mode, simulate a successful connection
    send(state.subscriber, {:ssh_connected})
    # Send a fake banner after a short delay
    Process.send_after(self(), :mock_banner, 100)
    {:noreply, state}
  end

  defp handle_mock_input(data, state) do
    # Echo input back with a fake prompt
    response = "#{data}\r\nmock@tunneld:~$ "
    send(state.subscriber, {:ssh_data, response})
    {:noreply, state}
  end

  # ───────────────────────────────────────────────────────────────────────────
  # Helpers
  # ───────────────────────────────────────────────────────────────────────────

  defp ensure_integer(val) when is_integer(val), do: val
  defp ensure_integer(val) when is_binary(val), do: String.to_integer(val)
  defp ensure_integer(_), do: 22

  defp format_error(:machine_not_found), do: "Machine not found"
  defp format_error(:no_key), do: "SSH key not found for this machine"
  defp format_error(:pty_alloc_failed), do: "Failed to allocate PTY on remote"
  defp format_error({:shell_failed, _}), do: "Failed to start shell"
  defp format_error({:channel_open_failed, _}), do: "Failed to open SSH channel"
  defp format_error({:pty_alloc_error, _}), do: "PTY allocation error"
  defp format_error({:user_dir_setup_failed, msg}), do: "Failed to setup SSH: #{msg}"
  defp format_error(:timeout), do: "Connection timed out"
  defp format_error(:econnrefused), do: "Connection refused - is SSH running on the target?"
  defp format_error(:ehostunreach), do: "Host unreachable - check the WireGuard overlay"
  defp format_error(reason) when is_atom(reason), do: "Connection failed: #{reason}"
  defp format_error(reason), do: "Connection failed: #{inspect(reason)}"
end

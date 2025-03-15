defmodule Sentinel.Servers.Cloudflare do
  @moduledoc """
  Extended GenServer-based Cloudflare tunnel manager.

  Features:
    • Creates a dedicated tunnel for each hostname.
    • Persists tunnel+hostname info in a JSON file.
    • On startup, reads the file and reconnects any existing tunnels.
    • Provides functions to create, route, run, and delete tunnels.

  We use:
    1) cloudflared tunnel create <TUNNEL_NAME>
    2) cloudflared tunnel route dns <TUNNEL_NAME> <HOSTNAME>
    3) cloudflared tunnel run --url <HOSTNAME> <TUNNEL_NAME>

  And now also do:
    • cloudflared tunnel cleanup <TUNNEL_NAME>
    before deleting a tunnel to avoid the “active connections” issue.
  """

  use GenServer
  require Logger

  @doc """
  Starts the GenServer under a supervisor.
  On init, we ensure the data file exists, read it,
  and restore any tunnels.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  @doc """
  Creates a brand-new tunnel for `hostname`, sets up DNS route,
  and runs it with the local URL you provide.
  Persists the new tunnel in the file so it auto-restores next time.
  """
  def add_host(hostname, local_url) do
    GenServer.call(__MODULE__, {:add_host, hostname, local_url})
  end

  @doc """
  Deletes the tunnel for `hostname`, removing it from Cloudflare,
  killing the local process, and removing from the file.

  Also calls 'cloudflared tunnel cleanup' first to get rid of stale connections.
  """
  def remove_host(hostname) do
    GenServer.call(__MODULE__, {:remove_host, hostname})
  end

  @doc """
  Lists all known hostnames currently tracked in the file.
  """
  def list_hosts do
    GenServer.call(__MODULE__, :list_hosts)
  end

  @doc """
  Returns a list of hostnames that are currently running.
  """
  def list_running_tunnels do
    GenServer.call(__MODULE__, :list_running)
  end

  # ----------------------------------------------------------------
  #  GenServer callbacks
  # ----------------------------------------------------------------

  @impl true
  def init(_opts) do
    Logger.info("Starting Cloudflare Tunnel GenServer...")

    # Ensure the file exists
    create_file_if_missing()

    # Read existing data from file
    case read_file() do
      {:ok, tunnels} ->
        Logger.info("Loaded tunnel data from file: #{inspect(tunnels)}")

        state = %{
          running_tunnels: %{},   # hostname => Port
          records: tunnels        # list of maps: [%{"hostname"=>..., "tunnel_name"=>..., "local_url"=>...}, ...]
        }

        # For each record, re-create environment
        Enum.each(tunnels, fn record ->
          do_restore_tunnel(record)
        end)

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to load existing tunnel data: #{reason}")
        state = %{
          running_tunnels: %{},
          records: []
        }
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:add_host, hostname, local_url}, _from, state) do
    if Enum.any?(state.records, &(&1["hostname"] == hostname)) do
      Logger.warn("Host #{hostname} is already known; skipping new tunnel.")
      {:reply, :ok, state}
    else
      tunnel_name = tunnel_name_for(hostname)

      # 1) create
      unless tunnel_exists?(tunnel_name) do
        do_create_tunnel(tunnel_name)
      end

      # 2) route
      do_add_dns_route(tunnel_name, hostname)

      # 3) run
      port = do_run_tunnel(tunnel_name, hostname)

      # 4) update file + state
      record = %{"hostname" => hostname, "tunnel_name" => tunnel_name, "local_url" => local_url}
      new_records = [record | state.records]
      new_running = Map.put(state.running_tunnels, hostname, port)
      new_state = %{state | running_tunnels: new_running, records: new_records}

      write_file(new_records)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:remove_host, hostname}, _from, state) do
    case Enum.find(state.records, &(&1["hostname"] == hostname)) do
      nil ->
        Logger.warn("No record found for hostname=#{hostname}")
        {:reply, :ok, state}

      record ->
        tunnel_name = record["tunnel_name"]
        # 1) stop local process
        new_state = stop_local_tunnel(hostname, state)

        # 2) cleanup + delete tunnel
        do_cleanup_tunnel(tunnel_name)
        do_delete_tunnel(tunnel_name)

        # 3) remove from file
        pruned_records = Enum.reject(new_state.records, &(&1["hostname"] == hostname))
        final_state = %{new_state | records: pruned_records}
        write_file(pruned_records)

        {:reply, :ok, final_state}
    end
  end

  def handle_call(:list_hosts, _from, state) do
    hostnames = Enum.map(state.records, & &1["hostname"])
    {:reply, hostnames, state}
  end

  def handle_call(:list_running, _from, state) do
    running = Map.keys(state.running_tunnels)
    {:reply, running, state}
  end

  # ----------------------------------------------------------------
  # Internal logic
  # ----------------------------------------------------------------

  defp do_restore_tunnel(%{"hostname" => hostname, "tunnel_name" => tunnel_name, "local_url" => _url}) do
    unless tunnel_exists?(tunnel_name) do
      do_create_tunnel(tunnel_name)
    end
    do_add_dns_route(tunnel_name, hostname)
    do_run_tunnel(tunnel_name, hostname)
  end

  defp stop_local_tunnel(hostname, state) do
    case Map.fetch(state.running_tunnels, hostname) do
      :error ->
        Logger.warn("No running tunnel for #{hostname}")
        state

      {:ok, port} ->
        Logger.info("Stopping local tunnel for #{hostname}")
        Port.close(port)
        new_map = Map.delete(state.running_tunnels, hostname)
        %{state | running_tunnels: new_map}
    end
  end

  defp do_create_tunnel(tunnel_name) do
    Logger.info("Creating tunnel: #{tunnel_name}")
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "create", tunnel_name], stderr_to_stdout: true)

    if exit_code != 0 do
      Logger.error("Failed to create tunnel:\n#{output}")
    else
      Logger.info("Tunnel `#{tunnel_name}` created successfully.")
    end
  end

  defp do_add_dns_route(tunnel_name, hostname) do
    Logger.info("Adding DNS route: #{hostname} -> #{tunnel_name}")
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "route", "dns", tunnel_name, hostname],
        stderr_to_stdout: true
      )
    if exit_code != 0 do
      Logger.error("Failed to add DNS route:\n#{output}")
    else
      Logger.info("DNS route for #{hostname} added successfully.")
    end
  end

  # Called before delete, to remove stale connections if present
  defp do_cleanup_tunnel(tunnel_name) do
    Logger.info("Cleaning up stale connections for tunnel: #{tunnel_name}")
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "cleanup", tunnel_name], stderr_to_stdout: true)

    if exit_code != 0 do
      Logger.warn("Tunnel cleanup error (possibly no stale connections):\n#{output}")
    else
      Logger.info("Tunnel `#{tunnel_name}` cleaned up (stale connections removed).")
    end
  end

  defp do_delete_tunnel(tunnel_name) do
    Logger.info("Deleting tunnel: #{tunnel_name}")
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "delete", tunnel_name], stderr_to_stdout: true)
    if exit_code != 0 do
      Logger.error("Failed to delete tunnel:\n#{output}")
    else
      Logger.info("Tunnel `#{tunnel_name}` deleted successfully.")
    end
  end

  defp do_run_tunnel(tunnel_name, hostname) do
    Logger.info("Running tunnel: #{tunnel_name} with --url #{hostname}...")
    Port.open({:spawn_executable, System.find_executable("cloudflared")}, [
      :binary,
      :exit_status,
      :hide,
      :use_stdio,
      args: ["tunnel", "run", "--url", hostname, tunnel_name]
    ])
  end

  defp tunnel_name_for(hostname),
    do: "sentinel-" <> String.replace(hostname, ".", "-")

  defp tunnel_exists?(tunnel_name) do
    {output, _exit_code} = System.cmd("cloudflared", ["tunnel", "list"], stderr_to_stdout: true)
    String.contains?(output, tunnel_name)
  end

  # ----------------------------------------------------------------
  # File-based persistence (borrowed from your Auth approach)
  # ----------------------------------------------------------------

  defp create_file_if_missing do
    unless file_exists?() do
      # Create a new file with empty array
      case File.write(path(), "[]") do
        :ok ->
          Logger.info("Created tunnel data file.")
        {:error, reason} ->
          Logger.error("Failed to create tunnel data file: #{inspect(reason)}")
      end
    end
  end

  defp read_file do
    case File.read(path()) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, decoded} ->
            {:ok, decoded} # expecting list
          {:error, err} ->
            {:error, "Failed to decode file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  defp write_file(records) when is_list(records) do
    json = Jason.encode!(records)
    case File.write(path(), json) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("Failed to write to data file: #{inspect(reason)}")
    end
  end

  defp file_exists? do
    File.exists?(path())
  end

  defp path do
    "./" <> config_fs(:root) <> config_fs(:tunnels)
  end

  # We assume you have a config for :sentinel, :fs => %{ root: "...", tunnels: "cloudflare_tunnels.json" }
  defp config_fs do
    Application.get_env(:sentinel, :fs)
  end
  defp config_fs(key), do: config_fs()[key]
end

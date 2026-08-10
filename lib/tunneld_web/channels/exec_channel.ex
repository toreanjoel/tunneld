defmodule TunneldWeb.ExecChannel do
  @moduledoc """
  Phoenix channel for interactive SSH terminal sessions.

  Security model:
  - MUST authenticate the operator using the same session mechanism as the
    dashboard (`Tunneld.Servers.Session.valid?/1` against the client_id).
  - A terminal is remote code execution as root on the target machine.
  - Every session open/close is logged to the audit log.
  - Credentials (SSH keys) never leave the server; only terminal I/O is
    transmitted over the channel.
  """
  use Phoenix.Channel
  require Logger

  alias Tunneld.Machines.SSH.Session
  alias Tunneld.Servers.Session, as: AuthSession
  alias Tunneld.Audit

  @impl true
  def join("exec:" <> machine_id, params, socket) do
    client_id = socket.assigns[:client_id]

    # SECURITY: Verify the operator has a valid dashboard session.
    # This is critical - a terminal is remote code execution as root.
    unless client_id && AuthSession.valid?(client_id) do
      Logger.warning("Unauthorized exec channel join attempt for machine #{machine_id}")
      {:error, %{reason: "unauthorized"}}
    else
      # Verify the machine exists
      case Tunneld.Machines.get(machine_id) do
        {:ok, machine} ->
          cols = params["cols"] || 80
          rows = params["rows"] || 24

          # Audit log the session start
          Audit.log("terminal_open", machine_id, "started", client_id)

          # Start the SSH session GenServer, linked to this channel
          case Session.start_link(
                 machine_id: machine_id,
                 subscriber: self(),
                 cols: cols,
                 rows: rows
               ) do
            {:ok, session_pid} ->
              socket =
                socket
                |> assign(:session_pid, session_pid)
                |> assign(:machine_id, machine_id)
                |> assign(:machine_name, machine["name"] || machine_id)

              {:ok, socket}

            {:error, reason} ->
              Logger.error("Failed to start SSH session for #{machine_id}: #{inspect(reason)}")
              Audit.log("terminal_open", machine_id, "failed: #{inspect(reason)}", client_id)
              {:error, %{reason: "Failed to start SSH session"}}
          end

        {:error, _} ->
          {:error, %{reason: "Machine not found"}}
      end
    end
  end

  @impl true
  def handle_in("data", %{"data" => data}, socket) when is_binary(data) do
    # Send keystrokes to the SSH session
    if pid = socket.assigns[:session_pid] do
      Session.send_data(pid, data)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("resize", %{"cols" => cols, "rows" => rows}, socket)
      when is_integer(cols) and is_integer(rows) do
    # Handle terminal resize
    if pid = socket.assigns[:session_pid] do
      Session.resize(pid, cols, rows)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:noreply, socket}
  end

  # SSH session connected
  @impl true
  def handle_info({:ssh_connected}, socket) do
    push(socket, "connected", %{})
    {:noreply, socket}
  end

  # SSH data from remote
  @impl true
  def handle_info({:ssh_data, data}, socket) do
    push(socket, "data", %{data: Base.encode64(data)})
    {:noreply, socket}
  end

  # SSH session closed
  @impl true
  def handle_info({:ssh_closed, reason}, socket) do
    push(socket, "closed", %{reason: reason})
    {:noreply, socket}
  end

  # SSH error
  @impl true
  def handle_info({:ssh_error, reason}, socket) do
    push(socket, "error", %{reason: reason})
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    machine_id = socket.assigns[:machine_id]
    client_id = socket.assigns[:client_id]

    # Clean up the SSH session if it's still running
    if pid = socket.assigns[:session_pid] do
      if Process.alive?(pid) do
        Session.stop(pid)
      end
    end

    # Audit log the session end
    if machine_id && client_id do
      Audit.log("terminal_close", machine_id, "closed", client_id)
    end

    :ok
  end
end

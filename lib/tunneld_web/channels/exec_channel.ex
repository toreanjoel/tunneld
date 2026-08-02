defmodule TunneldWeb.ExecChannel do
  @moduledoc """
  Phoenix channel that streams an interactive `incus exec` session to the
  browser.

  Topic: `exec:<machine_id>:<container_name>`

  Events from client:
    `input`  - `{data: "keystrokes"}` written to the SSH stdin
    `resize` - `{cols: 80, rows: 24}` (ignored in v1, accepted for compat)

  Events from server:
    `output` - `{data: "stdout/stderr bytes"}`
    `exit`   - `{code: 0}`
  """

  use Phoenix.Channel
  require Logger

  alias Tunneld.Machines.Store
  alias Tunneld.Machines.Exec

  @impl true
  def join("exec:" <> rest, _payload, socket) do
    [machine_id, container] = String.split(rest, ":", parts: 2)

    case Store.get(machine_id) do
      {:ok, _machine} ->
        {:ok, assign(socket, machine_id: machine_id, container: container, exec_pid: nil)}

      {:error, :not_found} ->
        {:error, %{reason: "machine not found"}}
    end
  end

  @impl true
  def handle_in("start", _payload, socket) do
    machine_id = socket.assigns.machine_id
    container = socket.assigns.container

    with {:ok, machine} <- Store.get(machine_id),
         {:ok, pid} <- Exec.start(machine, container, self()) do
      {:reply, :ok, assign(socket, :exec_pid, pid)}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("input", %{"data" => data}, socket) do
    if pid = socket.assigns.exec_pid do
      Exec.send_input(pid, data)
    end

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("resize", _payload, socket) do
    # PTY resize is not implemented in v1 (would need to signal the SSH process).
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in(_other, _payload, socket) do
    {:reply, {:error, %{reason: "unknown event"}}, socket}
  end

  # Messages from the Exec process

  @impl true
  def handle_info({:exec_output, data}, socket) do
    push(socket, "output", %{data: data})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:exec_exit, code}, socket) do
    push(socket, "exit", %{code: code})
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if pid = socket.assigns[:exec_pid] do
      Exec.stop(pid)
    end

    :ok
  end
end
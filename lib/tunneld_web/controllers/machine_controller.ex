defmodule TunneldWeb.MachineController do
  @moduledoc """
  HTTP API for machine enrollment and management.

  v1 gating: admin session (same auth as the dashboard).

  Endpoints (under /api/v1):
    GET    /machines            list enrolled machines
    POST   /machines            enroll a new machine (returns public key to install)
    GET    /machines/:id        fetch one machine
    POST   /machines/:id/probe   re-probe capabilities (live over SSH)
    DELETE /machines/:id        remove machine and delete its keypair
  """

  use TunneldWeb, :controller
  require Logger

  plug :require_admin when action in [:index, :show, :listeners, :create, :probe, :delete]

  def index(conn, _params) do
    json(conn, %{machines: Tunneld.Machines.list()})
  end

  def show(conn, %{"id" => id}) do
    case Tunneld.Machines.get(id) do
      {:ok, machine} -> json(conn, %{machine: machine})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  def create(conn, params) do
    case Tunneld.Machines.enroll(params) do
      {:ok, %{"id" => id, "public_key" => pub, "machine" => machine}} ->
        conn
        |> put_status(201)
        |> json(%{
          id: id,
          machine: machine,
          public_key: pub,
          instructions: "Install this key on the target's ~/.ssh/authorized_keys, then POST /api/v1/machines/#{id}/probe"
        })

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: reason})
    end
  end

  def probe(conn, %{"id" => id}) do
    case Tunneld.Machines.probe(id) do
      {:ok, machine} -> json(conn, %{machine: machine})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "not found"})
      {:error, :incus_not_installed} -> conn |> put_status(424) |> json(%{error: "incus not installed on target"})
      {:error, reason} -> conn |> put_status(502) |> json(%{error: "probe failed", detail: inspect(reason)})
    end
  end

  def listeners(conn, %{"id" => id}) do
    case Tunneld.Machines.listeners(id) do
      {:ok, listeners} -> json(conn, %{listeners: listeners})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "not found"})
      {:error, reason} -> conn |> put_status(502) |> json(%{error: "list failed", detail: inspect(reason)})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Tunneld.Machines.remove(id) do
      :ok -> conn |> put_status(204) |> send_resp(204, "")
      {:error, _} -> conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  # Job-based probe: enqueue, return 202 {job_id}; poll /agent/jobs/:id.
  def probe_job(conn, %{"id" => id}) do
    {job_id, _pid} = Tunneld.Jobs.enqueue(fn -> Tunneld.Machines.probe(id) end)
    conn |> put_status(202) |> json(%{job_id: job_id, status: "running"})
  end

  # Run a command on a machine over SSH (scoped to `exec`). Returns job.
  def exec(conn, %{"id" => id} = params) do
    cmd = params["cmd"] || "true"

    case Tunneld.Machines.get(id) do
      {:ok, machine} ->
        {job_id, _pid} =
          Tunneld.Jobs.enqueue(fn ->
            Tunneld.Machines.SSH.run(machine, cmd)
          end)

        conn |> put_status(202) |> json(%{job_id: job_id, status: "running"})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "machine not found"})
    end
  end

  # --- Auth ---

  defp require_admin(conn, _opts) do
    # Agent-API routes carry an agent_scope in conn.private (auth handled by
    # the AgentAuth plug); skip the session check for those.
    if Map.has_key?(conn.private, :agent_scope) do
      conn
    else
      client_id = get_session(conn, :client_id)

      if client_id && Tunneld.Servers.Session.valid?(client_id) do
        conn
      else
        conn
        |> put_status(401)
        |> json(%{error: "admin session required"})
        |> halt()
      end
    end
  end
end
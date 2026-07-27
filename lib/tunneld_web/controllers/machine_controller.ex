defmodule TunneldWeb.MachineController do
  @moduledoc """
  HTTP API for machine enrollment and management.

  v1 gating: admin session (same auth as the dashboard). The per-device
  allowlist path (for subnet devices to self-provision) arrives with
  container provisioning in a later milestone.

  Endpoints (under /api/v1):
    GET    /machines            list enrolled machines
    POST   /machines            enroll a new machine (returns public key to install)
    GET    /machines/:id        fetch one machine
    POST   /machines/:id/probe   re-probe capabilities (live over SSH)
    GET    /machines/:id/containers  list containers/VMs (live)
    DELETE /machines/:id        remove machine and delete its keypair
  """

  use TunneldWeb, :controller
  require Logger

  plug :require_admin when action in [:create, :probe, :delete]

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

  def containers(conn, %{"id" => id}) do
    case Tunneld.Machines.list_containers(id) do
      {:ok, containers} -> json(conn, %{containers: containers})
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

  # --- Auth ---

  defp require_admin(conn, _opts) do
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
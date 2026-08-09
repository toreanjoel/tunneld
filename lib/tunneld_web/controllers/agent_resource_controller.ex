defmodule TunneldWeb.AgentResourceController do
  @moduledoc """
  Agent API resource endpoints (scoped bearer-token auth via `AgentAuth`).

    GET    /api/v1/resources            list resources          (resources:read)
    POST   /api/v1/resources            create a resource       (resources:write)
    DELETE /api/v1/resources/:id        remove a resource       (resources:write)
    GET    /api/v1/jobs/:id             fetch a job result      (any)

  Resources are created exactly like the dashboard: they become a Caddy config
  (LAN + loopback planes) via `Resources.add_share`.
  """

  use TunneldWeb, :controller

  alias Tunneld.Servers.Resources

  def index(conn, _params) do
    shares =
      Resources.fetch_shares()
      |> Enum.map(fn r ->
        %{
          id: r.id,
          name: r.name,
          pool: r.pool,
          lan_url: r.lan_url,
          loopback_port: r.loopback_port,
          health: r.health
        }
      end)

    json(conn, %{resources: shares})
  end

  def create(conn, params) do
    name = params["name"]
    pool = params["pool"] || []

    if is_binary(name) and is_list(pool) do
      result = Resources.add_share(%{"name" => name, "description" => params["description"], "pool" => pool})
      _ = result

      case Enum.find(Resources.fetch_shares(), &(&1.name == name)) do
        nil ->
          conn |> put_status(422) |> json(%{error: "could not create resource (name conflict or invalid pool)"})

        r ->
          conn
          |> put_status(201)
          |> json(%{id: r.id, name: r.name, lan_url: r.lan_url, loopback_port: r.loopback_port})
      end
    else
      conn |> put_status(422) |> json(%{error: "name (string) and pool (list) required"})
    end
  end

  def delete(conn, %{"id" => id}) do
    Resources.remove_share(id)
    json(conn, %{deleted: id})
  end

  def job(conn, %{"id" => id}) do
    case Tunneld.Jobs.get(id) do
      :not_found ->
        conn |> put_status(404) |> json(%{error: "job not found"})

      {:ok, %{status: status, result: result}} ->
        json(conn, %{id: id, status: status, result: result})
    end
  end
end

defmodule TunneldWeb.AgentTokenController do
  @moduledoc """
  Operator/admin token issuance for the agent API.

  Token issuance is a **forbidden scope** for API tokens (it would be privilege
  escalation), so it is only reachable via an admin **session** (same auth as
  the dashboard), never via a bearer token.

    POST /api/v1/agent/tokens   {scopes: ["machines:read", ...]}
    GET  /api/v1/agent/tokens   list issued tokens (id, scopes, created_at)
    DELETE /api/v1/agent/tokens/:id   revoke
  """

  use TunneldWeb, :controller
  plug :require_admin

  def create(conn, params) do
    scopes = params["scopes"] || []
    {:ok, raw, id, granted} = Tunneld.AgentTokens.issue(scopes)
    json(conn, %{token: raw, id: id, scopes: granted})
  end

  def index(conn, _params) do
    json(conn, %{tokens: Tunneld.AgentTokens.list()})
  end

  # Revocation by token id (needs the raw token or an id-based path). We store
  # only hashes; here we accept the raw token string to revoke.
  def delete(conn, %{"id" => token}) do
    Tunneld.AgentTokens.revoke(token)
    json(conn, %{revoked: true})
  end

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

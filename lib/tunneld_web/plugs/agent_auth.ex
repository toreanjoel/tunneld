defmodule TunneldWeb.Plugs.AgentAuth do
  @moduledoc """
  Authenticates agent API requests via a scoped `tnld_...` bearer token.

  The required scope is supplied per-route via `private: %{agent_scope: "..."}`
  in the router. Reads `Authorization: Bearer <token>`, verifies the token
  holds that scope via `Tunneld.AgentTokens`, records the call in the audit
  log, and halts with 401/403 on failure. On success assigns `:agent_token_id`
  and `:agent_scopes` to the connection.
  """

  import Plug.Conn

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = Map.get(conn.private, :agent_scope, "any")

    case bearer_token(conn) do
      nil ->
        conn
        |> put_status(401)
        |> json(%{error: "missing bearer token"})
        |> halt()

      token ->
        # scope "any" means "any valid token" (e.g. GET /jobs/:id); otherwise
        # the token must hold the requested scope.
        auth =
          if scope == "any" do
            Tunneld.AgentTokens.authorize_any(token)
          else
            Tunneld.AgentTokens.authorize(token, scope)
          end

        case auth do
          {:ok, token_id, scopes} ->
            _ = Tunneld.Audit.log(action(conn), target(conn), :ok, token_id)

            conn
            |> assign(:agent_token_id, token_id)
            |> assign(:agent_scopes, scopes)

          :error ->
            _ = Tunneld.Audit.log(action(conn), target(conn), :denied, "unknown")

            conn
            |> put_status(403)
            |> json(%{error: "invalid token or insufficient scope"})
            |> halt()
        end
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token |> String.trim()
      ["bearer " <> token] -> token |> String.trim()
      _ -> nil
    end
  end

  defp action(conn) do
    case Map.get(conn.private, :phoenix_action) do
      a when is_atom(a) -> Atom.to_string(a)
      a -> to_string(a || "api")
    end
  end

  defp target(conn), do: conn.request_path || ""

  defp json(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 400, Jason.encode!(body))
  end
end

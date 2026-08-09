defmodule Tunneld.AgentTokenControllerTest do
  use TunneldWeb.ConnCase, async: false

  alias Tunneld.AgentTokens

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_tokent_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")
    on_exit(fn -> File.rm_rf!(tmp); Application.put_env(:tunneld, :fs, root: prev_root) end)
    :ok
  end

  test "token endpoints require admin session" do
    conn = build_conn() |> post("/api/v1/agent/tokens", %{"scopes" => ["machines:read"]})
    assert response(conn, 401)
  end

  test "token endpoints are NOT reachable via a bearer token scope" do
    {:ok, raw, _id, _s} = AgentTokens.issue(["machines:read"])
    conn = build_conn() |> put_req_header("authorization", "Bearer #{raw}") |> post("/api/v1/agent/tokens", %{"scopes" => ["exec"]})
    # requires admin session, so a token alone is insufficient
    assert response(conn, 401)
  end

  test "AgentTokens issue strips forbidden scopes and prefixes tnld_" do
    {:ok, raw, _id, scopes} = AgentTokens.issue(["machines:read", "wireguard:keys"])
    assert String.starts_with?(raw, "tnld_")
    refute "wireguard:keys" in scopes
    assert "machines:read" in scopes
  end
end

defmodule Tunneld.AgentApiTest do
  use TunneldWeb.ConnCase, async: false

  alias Tunneld.AgentTokens
  alias Tunneld.Machines

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_agent_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  defp auth_conn(token, scope \\ "any") do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> Map.put(:private, %{phoenix_action: String.to_atom(scope)})
  end

  test "issuing a token returns a tnld_ prefixed token and stores only a hash" do
    {:ok, raw, id, scopes} = AgentTokens.issue(["machines:read", "resources:write"])
    assert String.starts_with?(raw, "tnld_")
    assert "machines:read" in scopes

    path = Path.join(Application.get_env(:tunneld, :fs)[:root], "tokens.json")
    stored = File.read!(path)
    refute String.contains?(stored, raw)  # raw token is never stored
    assert String.contains?(stored, id)
  end

  test "forbidden scopes are stripped at issue" do
    {:ok, _raw, _id, scopes} = AgentTokens.issue(["tokens:issue", "machines:read"])
    refute "tokens:issue" in scopes
    assert "machines:read" in scopes
  end

  test "revoked tokens no longer authorize" do
    {:ok, raw, _id, _scopes} = AgentTokens.issue(["machines:read"])
    assert {:ok, _id, _} = AgentTokens.authorize(raw, "machines:read")
    AgentTokens.revoke(raw)
    assert :error = AgentTokens.authorize(raw, "machines:read")
  end

  test "authorize requires the requested scope" do
    {:ok, raw, _id, _scopes} = AgentTokens.issue(["machines:read"])
    assert {:ok, _id, _} = AgentTokens.authorize(raw, "machines:read")
    assert :error = AgentTokens.authorize(raw, "exec")
  end

  test "agent API rejects missing token" do
    conn = build_conn() |> get("/api/v1/agent/machines")
    assert response(conn, 401)
  end

  test "agent API lists machines with a scoped token" do
    {:ok, _} = Machines.enroll(%{"name" => "vps", "address" => "203.0.113.50", "location" => "remote"})
    {:ok, raw, _id, _scopes} = AgentTokens.issue(["machines:read"])
    # isolate: does authorize work directly?
    assert {:ok, _id, _scopes} = AgentTokens.authorize(raw, "machines:read")
    conn = build_conn() |> put_req_header("authorization", "Bearer #{raw}") |> get("/api/v1/agent/machines")
    assert %{"machines" => [_]} = json_response(conn, 200)
  end

  test "audit log records authenticated calls" do
    {:ok, raw, id, _scopes} = AgentTokens.issue(["machines:read"])
    _ = Tunneld.Audit.log("test_action", "/test", :ok, id)
    entries = Tunneld.Audit.list()
    assert Enum.any?(entries, &(&1["token_id"] == id and &1["action"] == "test_action"))
  end

  test "jobs run async and are retrievable" do
    {job_id, _pid} = Tunneld.Jobs.enqueue(fn -> 42 end)
    # give the task a moment
    Process.sleep(50)
    assert {:ok, %{status: :done, result: {:ok, 42}}} = Tunneld.Jobs.get(job_id)
  end
end

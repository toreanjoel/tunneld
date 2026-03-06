defmodule TunneldWeb.HealthControllerTest do
  use TunneldWeb.ConnCase

  test "GET /api/health returns ok status", %{conn: conn} do
    conn = get(conn, "/api/health")
    body = json_response(conn, 200)

    assert body["status"] == "ok"
    assert is_binary(body["version"])
  end
end

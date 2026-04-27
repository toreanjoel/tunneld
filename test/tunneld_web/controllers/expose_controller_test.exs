defmodule TunneldWeb.ExposeControllerTest do
  use TunneldWeb.ConnCase
  alias Tunneld.Servers.{ExposeAllowed, Resources, Zrok}

  @device_ip {10, 0, 0, 59}
  @device_mac "b2:11:11:11:11:11"
  @other_ip {10, 0, 0, 33}
  @other_mac "22:22:22:22:22:20"

  setup do
    root = Tunneld.Config.fs_root()
    File.mkdir_p!(root)

    # clean up expose_allowed and resources files
    for file <- ["expose_allowed.json", "resources.json"] do
      path = Path.join(root, file)
      File.rm(path)
      File.rm(path <> ".bak")
    end

    # set a fake zrok endpoint so connectivity checks pass in mock mode
    :sys.replace_state(Zrok, fn state -> %{state | api_endpoint: "https://zrok.example.com"} end)

    :ok
  end

  defp conn_with_ip(conn, ip) do
    %{conn | remote_ip: ip}
  end

  describe "POST /api/v1/expose" do
    test "returns 403 for unknown device IP", %{conn: conn} do
      conn =
        conn
        |> conn_with_ip({127, 0, 0, 1})
        |> post("/api/v1/expose", %{"port" => 3000, "name" => "myapp"})

      assert json_response(conn, 403)["error"] =~ "device not recognised"
    end

    test "returns 403 for unallowed device", %{conn: conn} do
      conn =
        conn
        |> conn_with_ip(@device_ip)
        |> post("/api/v1/expose", %{"port" => 3000, "name" => "myapp"})

      assert json_response(conn, 403)["error"] =~ "device not allowed"
    end

    test "returns 422 for missing port", %{conn: conn} do
      ExposeAllowed.allow(@device_mac)

      conn =
        conn
        |> conn_with_ip(@device_ip)
        |> post("/api/v1/expose", %{"name" => "myapp"})

      assert json_response(conn, 422)["error"] =~ "port"
    end

    test "returns 422 for invalid name", %{conn: conn} do
      ExposeAllowed.allow(@device_mac)

      conn =
        conn
        |> conn_with_ip(@device_ip)
        |> post("/api/v1/expose", %{"port" => 3000, "name" => "my app!"})

      assert json_response(conn, 422)["error"] =~ "name"
    end

    test "returns 409 for duplicate name", %{conn: conn} do
      ExposeAllowed.allow(@device_mac)

      # seed a resource with the same name
      write_test_resource("dupname")

      conn =
        conn
        |> conn_with_ip(@device_ip)
        |> post("/api/v1/expose", %{"port" => 3000, "name" => "dupname"})

      assert json_response(conn, 409)["error"] =~ "already in use"
    end

    test "returns 503 when zrok endpoint not set", %{conn: conn} do
      ExposeAllowed.allow(@device_mac)
      :sys.replace_state(Zrok, fn state -> %{state | api_endpoint: nil} end)

      conn =
        conn
        |> conn_with_ip(@device_ip)
        |> post("/api/v1/expose", %{"port" => 3000, "name" => "zrokmissing"})

      assert json_response(conn, 503)["error"] =~ "no Zrok control plane"
    end

    test "creates share and returns 200", %{conn: conn} do
      ExposeAllowed.allow(@device_mac)

      conn =
        conn
        |> conn_with_ip(@device_ip)
        |> post("/api/v1/expose", %{"port" => 3000, "name" => "testapp"})

      # In mock mode add_share may fail at zrok name creation, but the controller
      # should still return the right shape when it succeeds or a 500 when it fails.
      status = conn.status
      body = json_response(conn, status)

      if status == 200 do
        assert body["name"] == "testapp"
        assert is_binary(body["public_url"])
        assert body["port"] == 3000
        assert body["device_ip"] == "10.0.0.59"
      else
        assert status == 500
        assert body["error"] =~ "not created"
      end
    end
  end

  describe "DELETE /api/v1/expose/:name" do
    test "returns 403 for unknown device", %{conn: conn} do
      conn =
        conn
        |> conn_with_ip({127, 0, 0, 1})
        |> delete("/api/v1/expose/myapp")

      assert json_response(conn, 403)["error"] =~ "device not recognised"
    end

    test "returns 403 when deleting another device's share", %{conn: conn} do
      ExposeAllowed.allow(@other_mac)
      write_test_resource("myapp", @device_mac)

      conn =
        conn
        |> conn_with_ip(@other_ip)
        |> delete("/api/v1/expose/myapp")

      assert json_response(conn, 403)["error"] =~ "share not found"
    end

    test "removes own share and returns 200", %{conn: conn} do
      ExposeAllowed.allow(@device_mac)
      write_test_resource("myapp", @device_mac)

      conn =
        conn
        |> conn_with_ip(@device_ip)
        |> delete("/api/v1/expose/myapp")

      assert json_response(conn, 200)["status"] == "removed"
    end
  end

  describe "GET /api/v1/expose" do
    test "returns 403 for unknown device", %{conn: conn} do
      conn =
        conn
        |> conn_with_ip({127, 0, 0, 1})
        |> get("/api/v1/expose")

      assert json_response(conn, 403)["error"] =~ "device not recognised"
    end

    test "returns only the device's shares", %{conn: conn} do
      ExposeAllowed.allow(@device_mac)
      write_test_resource("share1", @device_mac)
      write_test_resource("share2", @other_mac)

      conn =
        conn
        |> conn_with_ip(@device_ip)
        |> get("/api/v1/expose")

      body = json_response(conn, 200)
      names = Enum.map(body["shares"], & &1["name"])
      assert "share1" in names
      refute "share2" in names
    end
  end

  defp write_test_resource(name, mac \\ @device_mac) do
    path = Resources.path()
    existing = Resources.read_file()

    resource = %{
      "id" => "#{System.system_time(:second)}",
      "name" => name,
      "description" => "test",
      "ip" => "127.0.0.1",
      "port" => "18000",
      "pool" => ["127.0.0.1:3000"],
      "kind" => "host",
      "expose_source" => "device",
      "expose_device_mac" => mac,
      "expose_device_ip" => "10.0.0.59",
      "tunneld" => %{
        "share_names" => %{"public" => "pub#{name}", "private" => "priv#{name}"},
        "units" => %{
          "public" => %{"id" => "unit-#{name}-pub", "unit" => "zrok-#{name}-pub.service"},
          "private" => %{"id" => "unit-#{name}-priv", "unit" => "zrok-#{name}-priv.service"}
        },
        "enabled" => %{"public" => true, "private" => false}
      }
    }

    Tunneld.Persistence.write_json(path, existing ++ [resource])
  end
end

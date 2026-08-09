defmodule TunneldWeb.DeviceControllerTest do
  use TunneldWeb.ConnCase, async: false

  alias Tunneld.Machines

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_device_ctl_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  defp device_conn(conn, ip \\ {10, 0, 0, 59}) do
    %{conn | remote_ip: ip}
  end

  test "machines list requires a known subnet device" do
    conn = build_conn() |> device_conn({192, 168, 99, 99}) |> get("/api/v1/device/machines")
    assert response(conn, 403)
  end

  test "machines list returns enrolled machines" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps", "address" => "203.0.113.5", "location" => "remote"})

    conn = build_conn() |> device_conn() |> get("/api/v1/device/machines")
    assert %{"machines" => [m]} = json_response(conn, 200)
    assert m["id"] == id
    assert m["name"] == "vps"
    assert m["location"] == "remote"
  end

  test "machine detail returns health" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box", "address" => "10.0.0.5"})

    conn = build_conn() |> device_conn() |> get("/api/v1/device/machines/#{id}")
    assert %{"machine" => m, "health" => health} = json_response(conn, 200)
    assert m["id"] == id
    assert health["probed"] == false
  end

  test "resources returns exposed resources" do
    conn = build_conn() |> device_conn() |> get("/api/v1/device/resources")
    assert %{"resources" => resources} = json_response(conn, 200)
    assert is_list(resources)
  end

  test "health returns gateway status and services" do
    conn = build_conn() |> device_conn() |> get("/api/v1/device/health")
    assert %{"status" => "ok", "services" => services} = json_response(conn, 200)
    assert is_list(services)
  end
end

defmodule Tunneld.EgressTest do
  use ExUnit.Case, async: false

  alias Tunneld.Egress
  alias Tunneld.Machines

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_egress_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")
    on_exit(fn -> File.rm_rf!(tmp); Application.put_env(:tunneld, :fs, root: prev_root) end)
    :ok
  end

  test "route_device returns an egress mapping (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps", "address" => "203.0.113.9", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    {:ok, res} = Egress.route_device(m, "10.0.0.100")
    assert res.device_ip == "10.0.0.100"
    assert res.machine == id
    assert is_binary(res.table)
    assert res.dns == "local"
  end

  test "table ids are stable per machine" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps2", "address" => "203.0.113.10", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    assert Egress.table_for(m) == Egress.table_for(m)
  end

  test "table ids are unique across machines" do
    {:ok, %{"id" => id1}} = Machines.enroll(%{"name" => "a", "address" => "203.0.113.20", "location" => "remote"})
    {:ok, %{"id" => id2}} = Machines.enroll(%{"name" => "b", "address" => "203.0.113.21", "location" => "remote"})
    {:ok, m1} = Machines.get(id1)
    {:ok, m2} = Machines.get(id2)
    refute Egress.table_for(m1) == Egress.table_for(m2)
  end

  test "unroute_device is idempotent (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps3", "address" => "203.0.113.11", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    assert :ok = Egress.unroute_device(m, "10.0.0.101")
    assert :ok = Egress.unroute_device(m, "10.0.0.101")
  end

  test "route_device persists the device->machine mapping and unroute clears it" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps4", "address" => "203.0.113.12", "location" => "remote"})
    {:ok, m} = Machines.get(id)

    # not routed yet
    assert Egress.device_egress("10.0.0.200") == nil

    {:ok, _} = Egress.route_device(m, "10.0.0.200")
    assert Egress.device_egress("10.0.0.200") == id
    assert Egress.device_egress_map()["10.0.0.200"] == id

    # unroute clears it
    :ok = Egress.unroute_device(m, "10.0.0.200")
    assert Egress.device_egress("10.0.0.200") == nil
  end

  test "ensure_exit_capable returns :ok in mock mode" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps4", "address" => "203.0.113.12", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    assert :ok = Egress.ensure_exit_capable(m)
  end
end

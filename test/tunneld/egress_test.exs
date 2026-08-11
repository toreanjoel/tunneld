defmodule Tunneld.EgressTest do
  use ExUnit.Case, async: false

  alias Tunneld.Egress
  alias Tunneld.Machines

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_egress_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  test "route_device returns an egress mapping (mock mode)" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps", "address" => "203.0.113.9", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    {:ok, res} = Egress.route_device(m, "10.0.0.100")
    assert res.device_ip == "10.0.0.100"
    assert res.machine == id
    assert is_binary(res.table)
    assert res.dns == "local"
  end

  test "table ids are stable per machine" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps2", "address" => "203.0.113.10", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    assert Egress.table_for(m) == Egress.table_for(m)
  end

  test "table ids are unique across machines" do
    {:ok, %{"id" => id1}} =
      Machines.enroll(%{"name" => "a", "address" => "203.0.113.20", "location" => "remote"})

    {:ok, %{"id" => id2}} =
      Machines.enroll(%{"name" => "b", "address" => "203.0.113.21", "location" => "remote"})

    {:ok, m1} = Machines.get(id1)
    {:ok, m2} = Machines.get(id2)
    refute Egress.table_for(m1) == Egress.table_for(m2)
  end

  test "unroute_device is idempotent (mock mode)" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps3", "address" => "203.0.113.11", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    assert :ok = Egress.unroute_device(m, "10.0.0.101")
    assert :ok = Egress.unroute_device(m, "10.0.0.101")
  end

  test "route_device persists the device->machine mapping and unroute clears it" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps4", "address" => "203.0.113.12", "location" => "remote"})

    {:ok, m} = Machines.get(id)

    # not routed yet
    assert Egress.device_egress("10.0.0.200") == nil

    {:ok, _} = Egress.route_device(m, "10.0.0.200")
    assert Egress.device_egress("10.0.0.200") == id

    # unroute clears it
    :ok = Egress.unroute_device(m, "10.0.0.200")
    assert Egress.device_egress("10.0.0.200") == nil
  end

  test "cleanup_machine removes the table allocation and device mappings" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps5", "address" => "203.0.113.13", "location" => "remote"})

    {:ok, m} = Machines.get(id)

    {:ok, _} = Egress.route_device(m, "10.0.0.210")
    assert Egress.device_egress("10.0.0.210") == id
    assert Egress.exit_capable?(m)

    :ok = Egress.cleanup_machine(m)

    assert Egress.device_egress("10.0.0.210") == nil
    refute Egress.exit_capable?(m)
  end

  # Regression: ensure_exit_capable returned a bare :ok, which does not match
  # the caller's `match?({:ok, _}, result)`. A fully successful setup was
  # therefore typed as an error and rendered by a catch-all clause as
  # "Exit node configured for <uuid>". Pin the success shape.
  test "ensure_exit_capable returns an ok-tuple, not a bare :ok" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps4", "address" => "203.0.113.12", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    result = Egress.ensure_exit_capable(m)

    assert match?({:ok, _}, result),
           "callers pattern-match {:ok, _}; got #{inspect(result)}"

    {:ok, info} = result
    assert is_binary(info.iface)
    assert is_binary(info.table)
  end

  # Regression: exit_capable?/1 is defined as "has a table allocated", but
  # ensure_exit_capable never allocated one, so the machine stayed "not set" in
  # the UI no matter how many times the operator clicked Exit Node.
  test "ensure_exit_capable makes exit_capable? true" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps6", "address" => "203.0.113.14", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    refute Egress.exit_capable?(m)

    {:ok, _} = Egress.ensure_exit_capable(m)
    assert Egress.exit_capable?(m)
  end

  test "ensure_exit_capable is idempotent and keeps the same table" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps7", "address" => "203.0.113.15", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    {:ok, first} = Egress.ensure_exit_capable(m)
    {:ok, second} = Egress.ensure_exit_capable(m)
    assert first.table == second.table
  end
end

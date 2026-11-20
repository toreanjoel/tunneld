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

  # The exit machine's rules are installed as a script run by a unit, because
  # none of them survive the machine's reboot. This is the script, asserted
  # without an SSH connection: it is the only place the reboot-repair contract
  # can be tested.
  test "exit_script carries forwarding, NAT, FORWARD and the device return routes" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps8", "address" => "203.0.113.16", "location" => "remote"})

    wg = Tunneld.Overlay.iface_name(id)
    script = Egress.exit_script(id, "eth0", ["10.0.0.50", "10.0.0.51", "10.0.0.50"])

    assert script =~ "net.ipv4.ip_forward=1"
    assert script =~ "iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE"
    assert script =~ "iptables -C FORWARD -i #{wg} -o eth0 -j ACCEPT"
    assert script =~ "iptables -C FORWARD -i eth0 -o #{wg} -m conntrack"
    # every rule is -C checked first, so re-running the unit changes nothing
    assert script =~ "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"

    # one route per device, deduplicated, `replace` so a rerun cannot fail
    assert length(Enum.reject(script |> String.split("\n"), &(String.trim(&1) == ""))) ==
             Enum.count(Enum.uniq(["10.0.0.50", "10.0.0.51"])) + 4

    assert script =~ "ip route replace 10.0.0.50/32 dev #{wg}"
    assert script =~ "ip route replace 10.0.0.51/32 dev #{wg}"
    refute script =~ "ip route add"
  end

  test "gateway egress restore is safe with nothing to restore" do
    assert :ok = Egress.restore_all()

    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps9", "address" => "203.0.113.17", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    assert :ok = Egress.ensure_gateway_rules(m)
    assert :ok = Egress.restore_targets()
  end

  test "an exit-capable machine reports its rules as current in mock mode" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps10", "address" => "203.0.113.18", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    refute Egress.rules_current?(m)
    {:ok, _} = Egress.ensure_exit_capable(m)
    assert Egress.rules_current?(m)
  end

  # A WireGuard repair restarts the interface on both ends, which deletes the
  # policy table's default route and the VM's per-device return routes. The drift
  # check has to see that, or the repair pass leaves the device black-holed while
  # reporting everything current.
  test "the drift probes check the routes, not just iptables" do
    target = Egress.target_check_command("wg-abcd1234", "eth0", ["10.0.0.50", "10.0.0.51"])

    assert target =~ "iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE"
    assert target =~ "ip route show dev wg-abcd1234"
    assert target =~ "10.0.0.50"
    assert target =~ "10.0.0.51"
    # ip_forward's `1` must stay the last thing printed
    assert target =~ ~r/sysctl -n net.ipv4.ip_forward && ip route show/

    gateway = Egress.gateway_check_command("wg-abcd1234", "100")
    assert gateway =~ "iptables -C FORWARD -i eth1 -o wg-abcd1234 -j ACCEPT"
    assert gateway =~ "grep -q 'lookup 100'"
    assert gateway =~ "ip route show table 100"
    assert gateway =~ "grep -q '^default'"
  end

  # Without PartOf, the WG repair restarts the interface and the exit unit never
  # re-runs, so the routes its script installs stay gone.
  test "the exit unit is coupled to its WireGuard unit" do
    unit = Egress.exit_unit("wg-abcd1234")
    assert unit =~ "Wants=wg-quick@wg-abcd1234.service"
    assert unit =~ "PartOf=wg-quick@wg-abcd1234.service"
    assert unit =~ "ExecStart=/usr/local/sbin/tunneld-exit"
  end
end

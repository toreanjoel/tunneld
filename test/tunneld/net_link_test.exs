defmodule Tunneld.NetLinkTest do
  use ExUnit.Case, async: true

  alias Tunneld.NetLink

  # Mock mode is enabled in test.exs, so NetLink reads from FakeData.ethernet/0.

  describe "upstream_iface/0 and downstream_iface/0" do
    test "return the configured interface names from app env" do
      Application.put_env(:tunneld, :network, gateway: "10.0.0.1", upstream: "eth0", downstream: "eth1")

      assert NetLink.upstream_iface() == "eth0"
      assert NetLink.downstream_iface() == "eth1"
    after
      Application.put_env(:tunneld, :network, gateway: "192.168.1.1", upstream: "eth0", downstream: "eth1")
    end

    test "return nil when the key is missing" do
      Application.put_env(:tunneld, :network, gateway: "10.0.0.1")

      assert NetLink.upstream_iface() == nil
      assert NetLink.downstream_iface() == nil
    after
      Application.put_env(:tunneld, :network, gateway: "192.168.1.1", upstream: "eth0", downstream: "eth1")
    end
  end

  describe "upstream_up?/0 and downstream_up?/0 in mock mode" do
    test "report up when FakeData.ethernet/0 has the interface up" do
      Application.put_env(:tunneld, :network, gateway: "10.0.0.1", upstream: "eth0", downstream: "eth1")

      assert NetLink.upstream_up?() == true
      assert NetLink.downstream_up?() == true
    after
      Application.put_env(:tunneld, :network, gateway: "192.168.1.1", upstream: "eth0", downstream: "eth1")
    end

    test "in mock mode always report up (matches legacy Wlan.connected? mock behaviour)" do
      # Mock mode short-circuits to FakeData.ethernet/0 before consulting the
      # configured iface name, so a missing :upstream key still reports up.
      Application.delete_env(:tunneld, :network)

      assert NetLink.upstream_up?() == true
      assert NetLink.downstream_up?() == true
    after
      Application.put_env(:tunneld, :network, gateway: "192.168.1.1", upstream: "eth0", downstream: "eth1")
    end
  end

  describe "status/0" do
    test "returns a map with both interfaces and their link state" do
      Application.put_env(:tunneld, :network, gateway: "10.0.0.1", upstream: "eth0", downstream: "eth1")

      status = NetLink.status()

      assert status.upstream == %{iface: "eth0", up: true}
      assert status.downstream == %{iface: "eth1", up: true}
    after
      Application.put_env(:tunneld, :network, gateway: "192.168.1.1", upstream: "eth0", downstream: "eth1")
    end

    test "reports nil iface but still up in mock mode (FakeData keys are present)" do
      Application.put_env(:tunneld, :network, gateway: "10.0.0.1")

      status = NetLink.status()

      # In mock mode, fake_state/1 matches on the :upstream/:downstream atom
      # key in FakeData.ethernet/0 - the configured iface name is not consulted.
      assert status.upstream == %{iface: nil, up: true}
      assert status.downstream == %{iface: nil, up: true}
    after
      Application.put_env(:tunneld, :network, gateway: "192.168.1.1", upstream: "eth0", downstream: "eth1")
    end
  end

  describe "upstream_up?/0 is resilient" do
    test "returns false when the operstate file is missing (non-mock)" do
      # In non-mock mode with a configured iface that has no sysfs entry,
      # iface_up? should return false rather than raise.
      Application.put_env(:tunneld, :mock_data, false)
      Application.put_env(:tunneld, :network, gateway: "10.0.0.1", upstream: "nonexistent0", downstream: "nonexistent1")

      assert NetLink.upstream_up?() == false
      assert NetLink.downstream_up?() == false
    after
      Application.put_env(:tunneld, :mock_data, true)
      Application.put_env(:tunneld, :network, gateway: "192.168.1.1", upstream: "eth0", downstream: "eth1")
    end
  end
end
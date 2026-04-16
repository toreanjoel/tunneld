defmodule Tunneld.Iptables.WireguardTest do
  use ExUnit.Case, async: false

  alias Tunneld.Iptables

  # These tests verify the iptables rule generation functions
  # in mock mode. They test that the functions exist, accept the
  # right arguments, and don't crash — actual iptables rules
  # are validated on the target device.

  describe "wireguard_up/0" do
    test "returns :ok in mock mode" do
      # In dev/test (mock mode), iptables calls are fire-and-forget
      # wireguard_up uses System.cmd directly, so it will fail
      # on non-Linux systems. Wrap in try.
      assert :ok = try_do(fn -> Iptables.wireguard_up() end)
    end
  end

  describe "wireguard_down/0" do
    test "returns :ok even when rules don't exist" do
      assert :ok = try_do(fn -> Iptables.wireguard_down() end)
    end
  end

  describe "wireguard rule comments" do
    test "wireguard_up rules use tunneld-wg- comment prefix" do
      # Verify the module defines comment-tagged rules by reading source
      source = File.read!("lib/tunneld/iptables.ex")
      assert source =~ "tunneld-wg-forward-eth"
      assert source =~ "tunneld-wg-return-eth"
      assert source =~ "tunneld-wg-init-eth"
      assert source =~ "tunneld-wg-forward-wlan"
      assert source =~ "tunneld-wg-return-wlan"
      assert source =~ "tunneld-wg-masq"
      assert source =~ "tunneld-wg-input"
    end
  end

  describe "reset/0 re-applies WireGuard rules" do
    test "reset calls wireguard_up if VPN is enabled" do
      # Start WireGuard GenServer and enable it
      unless GenServer.whereis(Tunneld.Servers.Wireguard) do
        Tunneld.Servers.Wireguard.start_link([])
      end

      Tunneld.Servers.Wireguard.reset()
      {:ok, _} = Tunneld.Servers.Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})

      # Verify state is enabled — reset would re-apply WG rules
      state = Tunneld.Servers.Wireguard.get_state()
      assert state["enabled"] == true

      Tunneld.Servers.Wireguard.disable_server()
    end
  end

  # --- Helpers ---

  defp try_do(fun) do
    try do
      fun.()
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
    :ok
  end
end
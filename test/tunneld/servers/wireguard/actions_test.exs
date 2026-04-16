defmodule TunneldWeb.Live.Dashboard.Actions.WireguardTest do
  use ExUnit.Case, async: false

  alias TunneldWeb.Live.Dashboard.Actions
  alias Tunneld.Servers.Wireguard

  setup do
    unless GenServer.whereis(Wireguard), do: Wireguard.start_link([])
    Wireguard.reset()
    :ok
  end

  describe "enable_wireguard action" do
    test "enables the VPN server via Actions.perform" do
      result = Actions.perform("enable_wireguard", %{}, self())
      assert {:ok, state} = result
      assert state["enabled"] == true
      assert state["subnet"] != nil
    end
  end

  describe "disable_wireguard action" do
    test "disables the VPN server via Actions.perform" do
      Wireguard.enable_server()
      result = Actions.perform("disable_wireguard", %{}, self())
      assert :ok = result
      assert Wireguard.get_state()["enabled"] == false
    end
  end

  describe "add_wireguard_peer action" do
    setup do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      :ok
    end

    test "adds a peer via Actions.perform" do
      data = %{"name" => "Phone", "full_tunnel" => true}
      result = Actions.perform("add_wireguard_peer", data, self())
      assert {:ok, peer, config} = result
      assert peer["name"] == "Phone"
      assert peer["full_tunnel"] == true
      assert is_binary(config)
      assert config =~ "[Interface]"
    end

    test "adds a split-tunnel peer by default" do
      data = %{"name" => "Laptop"}
      result = Actions.perform("add_wireguard_peer", data, self())
      assert {:ok, peer, _config} = result
      assert peer["full_tunnel"] == false
    end
  end

  describe "remove_wireguard_peer action" do
    setup do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      :ok
    end

    test "removes a peer via Actions.perform" do
      {:ok, peer, _} = Wireguard.add_peer("ToRemove")
      result = Actions.perform("remove_wireguard_peer", %{"peer_id" => peer["id"]}, self())
      assert :ok = result
      refute Map.has_key?(Wireguard.get_state()["peers"], peer["id"])
    end
  end

  describe "unknown wireguard action" do
    test "broadcasts error for unknown action" do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "notifications")
      Actions.perform("unknown_wireguard_action", %{}, self())

      assert_receive %{:type => :error, :message => msg}, 500
      assert msg =~ "doesnt exist"
    end
  end
end
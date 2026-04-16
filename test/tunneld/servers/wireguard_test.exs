defmodule Tunneld.Servers.WireguardTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Wireguard

  setup do
    unless GenServer.whereis(Wireguard), do: Wireguard.start_link([])
    Wireguard.reset()
    :ok
  end

  describe "get_state/0" do
    test "returns initial state with expected keys" do
      state = Wireguard.get_state()
      assert is_map(state)
      assert Map.has_key?(state, "enabled")
      assert Map.has_key?(state, "public_key")
      assert Map.has_key?(state, "private_key")
      assert Map.has_key?(state, "listen_port")
      assert Map.has_key?(state, "endpoint")
      assert Map.has_key?(state, "subnet")
      assert Map.has_key?(state, "peers")
    end

    test "initial state has server disabled" do
      state = Wireguard.get_state()
      assert state["enabled"] == false
    end
  end

  describe "enable_server/1 in mock mode" do
    test "enables the VPN server" do
      assert {:ok, state} = Wireguard.enable_server()
      assert state["enabled"] == true
      assert state["public_key"] != nil
      assert state["private_key"] != nil
      assert state["subnet"] != nil
    end

    test "generates a keypair on first enable" do
      {:ok, state} = Wireguard.enable_server()
      assert is_binary(state["public_key"])
      assert is_binary(state["private_key"])
      assert String.length(state["public_key"]) > 0
      assert String.length(state["private_key"]) > 0
    end

    test "generates a random subnet on first enable" do
      {:ok, state} = Wireguard.enable_server()
      subnet = state["subnet"]
      assert is_binary(subnet)
      assert Regex.match?(~r/^10\.\d{1,3}\.\d{1,3}\.0\/24$/, subnet)
    end

    test "uses default listen port" do
      {:ok, state} = Wireguard.enable_server()
      assert state["listen_port"] == 51820
    end

    test "accepts custom listen port" do
      {:ok, state} = Wireguard.enable_server(%{"listen_port" => 51821})
      assert state["listen_port"] == 51821
    end

    test "accepts custom subnet" do
      {:ok, state} = Wireguard.enable_server(%{"subnet" => "10.99.0.0/24"})
      assert state["subnet"] == "10.99.0.0/24"
    end

    test "accepts custom endpoint" do
      {:ok, state} = Wireguard.enable_server(%{"endpoint" => "myhome.ddns.net"})
      assert state["endpoint"] == "myhome.ddns.net"
    end

    test "returns ok if already enabled" do
      Wireguard.enable_server()
      assert {:ok, _} = Wireguard.enable_server()
    end
  end

  describe "disable_server/0 in mock mode" do
    test "disables the VPN server" do
      Wireguard.enable_server()
      assert :ok = Wireguard.disable_server()
      assert Wireguard.get_state()["enabled"] == false
    end

    test "returns ok if already disabled" do
      assert :ok = Wireguard.disable_server()
    end
  end

  describe "set_endpoint/1" do
    test "updates the endpoint" do
      Wireguard.enable_server()
      assert :ok = Wireguard.set_endpoint("203.0.113.1")
      assert Wireguard.get_state()["endpoint"] == "203.0.113.1"
    end
  end

  describe "server_ip/0" do
    test "returns nil when server not enabled" do
      assert Wireguard.server_ip() == nil
    end

    test "returns server IP from subnet" do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24"})
      assert Wireguard.server_ip() == "10.42.0.1/24"
    end
  end

  describe "add_peer/2 in mock mode" do
    setup do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      :ok
    end

    test "adds a split-tunnel peer" do
      assert {:ok, peer, config} = Wireguard.add_peer("Laptop", false)
      assert peer["name"] == "Laptop"
      assert peer["full_tunnel"] == false
      assert peer["ip"] == "10.42.0.2"
      assert is_binary(peer["public_key"])
      assert is_binary(peer["private_key"])
      assert is_binary(peer["id"])
      assert is_binary(config)
      assert config =~ "[Interface]"
      assert config =~ "[Peer]"
    end

    test "adds a full-tunnel peer" do
      assert {:ok, peer, _config} = Wireguard.add_peer("Phone", true)
      assert peer["full_tunnel"] == true
    end

    test "assigns sequential IPs" do
      {:ok, p1, _} = Wireguard.add_peer("Device1")
      {:ok, p2, _} = Wireguard.add_peer("Device2")
      assert p1["ip"] == "10.42.0.2"
      assert p2["ip"] == "10.42.0.3"
    end

    test "peer appears in state" do
      {:ok, peer, _config} = Wireguard.add_peer("Tablet")
      state = Wireguard.get_state()
      assert Map.has_key?(state["peers"], peer["id"])
      stored_peer = state["peers"][peer["id"]]
      assert stored_peer["name"] == "Tablet"
      # Private key NOT stored in state
      assert Map.has_key?(peer, "private_key")
      refute Map.has_key?(stored_peer, "private_key")
    end

    test "fails if server not enabled" do
      Wireguard.disable_server()
      assert {:error, :server_not_enabled} = Wireguard.add_peer("Ghost")
    end
  end

  describe "remove_peer/1 in mock mode" do
    setup do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      :ok
    end

    test "removes an existing peer" do
      {:ok, peer, _} = Wireguard.add_peer("ToGo")
      assert :ok = Wireguard.remove_peer(peer["id"])
      state = Wireguard.get_state()
      refute Map.has_key?(state["peers"], peer["id"])
    end

    test "returns error for unknown peer" do
      assert {:error, :not_found} = Wireguard.remove_peer("nonexistent")
    end
  end

  describe "regenerate_peer_config/1 in mock mode" do
    setup do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      :ok
    end

    test "generates new keypair for peer" do
      {:ok, peer, _} = Wireguard.add_peer("OldKeys")
      old_pub = peer["public_key"]

      assert {:ok, new_peer, config} = Wireguard.regenerate_peer_config(peer["id"])
      assert new_peer["public_key"] != old_pub
      assert Map.has_key?(new_peer, "private_key")
      assert new_peer["ip"] == peer["ip"]
      assert new_peer["name"] == peer["name"]
      assert is_binary(config)
      assert config =~ "[Interface]"
    end

    test "updates public key in state" do
      {:ok, peer, _} = Wireguard.add_peer("StateCheck")
      {:ok, _new_peer, _config} = Wireguard.regenerate_peer_config(peer["id"])

      state = Wireguard.get_state()
      stored = state["peers"][peer["id"]]
      assert stored["public_key"] != peer["public_key"]
    end

    test "returns error for unknown peer" do
      assert {:error, :not_found} = Wireguard.regenerate_peer_config("nonexistent")
    end
  end

  describe "state persistence across enable/disable" do
    test "retains keypair and subnet after disable" do
      {:ok, state} = Wireguard.enable_server(%{"subnet" => "10.42.0.0/24"})
      pub_key = state["public_key"]
      priv_key = state["private_key"]
      subnet = state["subnet"]

      Wireguard.disable_server()
      disabled_state = Wireguard.get_state()
      assert disabled_state["enabled"] == false
      # Keypair and subnet retained for re-enable
      assert disabled_state["public_key"] == pub_key
      assert disabled_state["private_key"] == priv_key
      assert disabled_state["subnet"] == subnet
    end

    test "persists state to wireguard.json" do
      {:ok, _state} = Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      assert Wireguard.file_exists?()

      data = Wireguard.get_state()
      assert data["enabled"] == true
      assert data["subnet"] == "10.42.0.0/24"
      assert data["endpoint"] == "1.2.3.4"
    end

    test "persists peers to wireguard.json" do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      {:ok, peer, _} = Wireguard.add_peer("PersistedPeer")

      data = Wireguard.get_state()
      assert Map.has_key?(data["peers"], peer["id"])
      stored = data["peers"][peer["id"]]
      assert stored["name"] == "PersistedPeer"
      refute Map.has_key?(stored, "private_key")
    end

    test "mock? is not persisted to disk" do
      Wireguard.enable_server()
      assert Wireguard.file_exists?()

      {:ok, raw} = Tunneld.Persistence.read_json(Wireguard.path?())
      refute Map.has_key?(raw, "mock?")
    end

    test "removing peer updates persisted state" do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      {:ok, peer, _} = Wireguard.add_peer("ToBeRemoved")
      assert :ok = Wireguard.remove_peer(peer["id"])

      data = Wireguard.get_state()
      refute Map.has_key?(data["peers"], peer["id"])
    end
  end

  describe "multiple peer operations" do
    setup do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      :ok
    end

    test "add then remove then add maintains IP sequence" do
      {:ok, p1, _} = Wireguard.add_peer("First")
      {:ok, p2, _} = Wireguard.add_peer("Second")
      assert p1["ip"] == "10.42.0.2"
      assert p2["ip"] == "10.42.0.3"

      Wireguard.remove_peer(p1["id"])
      {:ok, p3, _} = Wireguard.add_peer("Third")
      assert p3["ip"] == "10.42.0.4"
    end

    test "regenerate then remove works correctly" do
      {:ok, peer, _} = Wireguard.add_peer("RegenRemove")
      {:ok, _new_peer, _config} = Wireguard.regenerate_peer_config(peer["id"])
      assert :ok = Wireguard.remove_peer(peer["id"])
      refute Map.has_key?(Wireguard.get_state()["peers"], peer["id"])
    end

    test "peers have unique IDs" do
      {:ok, p1, _} = Wireguard.add_peer("A")
      {:ok, p2, _} = Wireguard.add_peer("B")
      {:ok, p3, _} = Wireguard.add_peer("C")
      ids = [p1["id"], p2["id"], p3["id"]]
      assert length(Enum.uniq(ids)) == 3
    end
  end

  describe "set_endpoint while server enabled" do
    test "updates endpoint without disrupting server" do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      assert :ok = Wireguard.set_endpoint("myhome.ddns.net")
      assert Wireguard.get_state()["endpoint"] == "myhome.ddns.net"
      assert Wireguard.get_state()["enabled"] == true
    end

    test "new peers use updated endpoint" do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      Wireguard.set_endpoint("new.endpoint.example")
      {:ok, _peer, config} = Wireguard.add_peer("Test")
      assert config =~ "new.endpoint.example"
    end
  end

  describe "re-enable preserves peers" do
    test "peers survive disable/enable cycle" do
      Wireguard.enable_server(%{"subnet" => "10.42.0.0/24", "endpoint" => "1.2.3.4"})
      {:ok, peer, _} = Wireguard.add_peer("Survivor")
      Wireguard.disable_server()
      {:ok, _state} = Wireguard.enable_server()

      state = Wireguard.get_state()
      assert Map.has_key?(state["peers"], peer["id"])
    end
  end

  # --- Helpers ---
end
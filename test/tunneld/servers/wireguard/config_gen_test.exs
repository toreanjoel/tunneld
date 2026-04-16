defmodule Tunneld.Servers.Wireguard.ConfigGenTest do
  use ExUnit.Case, async: true

  alias Tunneld.Servers.Wireguard.ConfigGen

  # --- Fixtures ---

  @server_state %{
    "enabled" => true,
    "private_key" => "sServerPrivateKeyBase64==",
    "public_key" => "sServerPublicKeyBase64==",
    "listen_port" => 51820,
    "endpoint" => "203.0.113.1",
    "subnet" => "10.42.0.0/24",
    "peers" => %{
      "100" => %{
        "id" => "100",
        "name" => "Laptop",
        "public_key" => "cLaptopPublicKeyBase64==",
        "ip" => "10.42.0.2",
        "full_tunnel" => false
      },
      "200" => %{
        "id" => "200",
        "name" => "Phone",
        "public_key" => "cPhonePublicKeyBase64==",
        "ip" => "10.42.0.3",
        "full_tunnel" => true
      }
    }
  }

  @split_peer %{
    "id" => "100",
    "name" => "Laptop",
    "private_key" => "cLaptopPrivateKeyBase64==",
    "public_key" => "cLaptopPublicKeyBase64==",
    "ip" => "10.42.0.2",
    "full_tunnel" => false
  }

  @full_peer %{
    "id" => "200",
    "name" => "Phone",
    "private_key" => "cPhonePrivateKeyBase64==",
    "public_key" => "cPhonePublicKeyBase64==",
    "ip" => "10.42.0.3",
    "full_tunnel" => true
  }

  describe "server_conf/1" do
    test "renders interface section with private key and listen port" do
      conf = ConfigGen.server_conf(@server_state)
      assert conf =~ "[Interface]"
      assert conf =~ "PrivateKey = sServerPrivateKeyBase64=="
      assert conf =~ "ListenPort = 51820"
    end

    test "renders all peers with public keys and allowed IPs" do
      conf = ConfigGen.server_conf(@server_state)
      assert conf =~ "[Peer]"
      assert conf =~ "PublicKey = cLaptopPublicKeyBase64=="
      assert conf =~ "AllowedIPs = 10.42.0.2/32"
      assert conf =~ "PublicKey = cPhonePublicKeyBase64=="
      assert conf =~ "AllowedIPs = 10.42.0.3/32"
    end

    test "renders empty peers section when no peers" do
      empty_state = Map.put(@server_state, "peers", %{})
      conf = ConfigGen.server_conf(empty_state)
      assert conf =~ "[Interface]"
      refute conf =~ "[Peer]"
    end
  end

  describe "peer_conf/2" do
    test "renders split-tunnel peer config" do
      conf = ConfigGen.peer_conf(@split_peer, @server_state)

      assert conf =~ "[Interface]"
      assert conf =~ "PrivateKey = cLaptopPrivateKeyBase64=="
      assert conf =~ "Address = 10.42.0.2/24"
      assert conf =~ "[Peer]"
      assert conf =~ "PublicKey = sServerPublicKeyBase64=="
      assert conf =~ "Endpoint = 203.0.113.1:51820"
      assert conf =~ "AllowedIPs = 10.42.0.0/24"
      assert conf =~ "PersistentKeepalive = 25"
    end

    test "renders full-tunnel peer config" do
      conf = ConfigGen.peer_conf(@full_peer, @server_state)

      assert conf =~ "AllowedIPs = 0.0.0.0/0"
      assert conf =~ "Address = 10.42.0.3/24"
    end

    test "includes DNS pointing to gateway" do
      # With network config set
      original = Application.get_env(:tunneld, :network)
      Application.put_env(:tunneld, :network, gateway: "192.168.1.1")

      conf = ConfigGen.peer_conf(@split_peer, @server_state)
      assert conf =~ "DNS = 192.168.1.1"

      Application.put_env(:tunneld, :network, original)
    end

    test "falls back to server IP for DNS when gateway not configured" do
      original = Application.get_env(:tunneld, :network)
      Application.put_env(:tunneld, :network, nil)

      conf = ConfigGen.peer_conf(@split_peer, @server_state)
      assert conf =~ "DNS = 10.42.0.1"

      Application.put_env(:tunneld, :network, original)
    end

    test "uses custom listen port in endpoint" do
      state = Map.put(@server_state, "listen_port", 51821)
      conf = ConfigGen.peer_conf(@split_peer, state)
      assert conf =~ "Endpoint = 203.0.113.1:51821"
    end

    test "uses DDNS hostname in endpoint" do
      state = Map.put(@server_state, "endpoint", "myhome.ddns.net")
      conf = ConfigGen.peer_conf(@split_peer, state)
      assert conf =~ "Endpoint = myhome.ddns.net:51820"
    end
  end

  describe "peer_conf_qr/2" do
    test "returns same content as peer_conf" do
      conf = ConfigGen.peer_conf(@split_peer, @server_state)
      qr = ConfigGen.peer_conf_qr(@split_peer, @server_state)
      assert conf == qr
    end

    test "is a valid string" do
      qr = ConfigGen.peer_conf_qr(@split_peer, @server_state)
      assert is_binary(qr)
      assert String.length(qr) > 0
    end
  end
end
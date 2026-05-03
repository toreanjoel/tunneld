defmodule Tunneld.Servers.WireguardTest do
  use ExUnit.Case, async: true

  alias Tunneld.Servers.Wireguard

  test "generate_keypair returns ok with keys in mock mode" do
    assert {:ok, priv, pub} = Wireguard.generate_keypair()
    assert is_binary(priv) and byte_size(priv) > 0
    assert is_binary(pub) and byte_size(pub) > 0
  end

  test "ensure_keypair generates keypair when missing" do
    # Reset to clear any existing keys
    Wireguard.reset()
    assert Wireguard.get_public_key() == nil

    :ok = Wireguard.ensure_keypair()
    pub = Wireguard.get_public_key()
    assert is_binary(pub) and byte_size(pub) > 0
  end
end

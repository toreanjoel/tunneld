defmodule Tunneld.ClientsTest do
  # A client peer is the one place tunneld hands out a private key, and the one
  # place where "trusted" still has to mean "scoped". These pin both.
  use ExUnit.Case, async: false

  alias Tunneld.Clients

  setup do
    root = Path.join(System.tmp_dir!(), "clients_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:tunneld, :fs)
    Application.put_env(:tunneld, :fs, root: root, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      if prev, do: Application.put_env(:tunneld, :fs, prev)
      File.rm_rf(root)
    end)

    :ok
  end

  test "enrolling returns a config containing the private key exactly once" do
    {:ok, client, config} = Clients.enroll("partner-phone")

    assert config =~ "[Interface]"
    assert config =~ "PrivateKey = "
    assert config =~ "Address = #{client["address"]}/32"
    assert config =~ "PersistentKeepalive = 25"

    # never persisted: revoking and re-enrolling is the recovery path
    refute File.read!(Path.join(Tunneld.Config.fs_root(), "clients.json")) =~ "PrivateKey"
    refute Map.has_key?(client, "private_key")
  end

  test "clients get sequential addresses in the client range, not the machine range" do
    {:ok, a, _} = Clients.enroll("laptop")
    {:ok, b, _} = Clients.enroll("phone")

    assert a["address"] == "10.88.1.2"
    assert b["address"] == "10.88.1.3"
    refute String.starts_with?(a["address"], "10.88.0.")
  end

  test "a fresh client reaches the overlay and nothing on the LAN" do
    {:ok, client, config} = Clients.enroll("guest")

    assert client["lan_access"] == []
    assert config =~ "AllowedIPs = 10.88.0.0/24, 10.88.1.0/24"
    refute config =~ "10.0.0."
  end

  test "granting LAN access names only the permitted hosts" do
    {:ok, client, _} = Clients.enroll("partner")
    {:ok, updated} = Clients.set_lan_access(client["id"], ["10.0.0.50", "10.0.0.51"])

    config = Clients.config_for(updated, "PRIVKEY")
    assert config =~ "10.0.0.50/32"
    assert config =~ "10.0.0.51/32"
    refute config =~ "10.0.0.0/24"
  end

  test "the gateway interface carries every client as its own /32 peer" do
    {:ok, a, _} = Clients.enroll("laptop")
    {:ok, b, _} = Clients.enroll("phone")

    conf = Clients.build_conf()
    assert conf =~ "ListenPort = 51822"
    assert conf =~ "Address = 10.88.1.1/24"
    assert conf =~ "Table = off"
    assert conf =~ "PublicKey = #{a["public_key"]}"
    assert conf =~ "AllowedIPs = #{b["address"]}/32"
  end

  test "revoking drops the peer from the gateway interface" do
    {:ok, a, _} = Clients.enroll("laptop")
    {:ok, b, _} = Clients.enroll("phone")

    :ok = Clients.revoke(a["id"])

    conf = Clients.build_conf()
    refute conf =~ a["public_key"]
    assert conf =~ b["public_key"]
    assert Clients.get(a["id"]) == nil
  end

  test "revoking something already gone is a no-op" do
    assert :ok = Clients.revoke("never-existed")
  end

  test "a blank name is refused rather than creating a nameless peer" do
    assert {:error, :name_required} = Clients.enroll("   ")
    assert Clients.list() == []
  end

  # The door only rewrites a destination into the tunnel that already exists.
  # If this ever grows a private key or a second wg instance, that is a bug.
  test "the machine door forwards the port into the overlay and holds no keys" do
    script = Clients.door_script()

    assert script =~ "--dport 51822"
    assert script =~ "DNAT --to-destination 10.88.0.1:51822"
    refute script =~ "PrivateKey"
    refute script =~ "wg-quick"
  end

  test "the client dials whichever endpoint it was issued for" do
    {:ok, home, cfg_home} = Clients.enroll("at-home", endpoint: "10.0.0.1")
    {:ok, _away, cfg_away} = Clients.enroll("away", endpoint: "139.84.235.70")

    assert cfg_home =~ "Endpoint = 10.0.0.1:51822"
    assert cfg_away =~ "Endpoint = 139.84.235.70:51822"
    assert home["endpoint"] == "10.0.0.1"
  end

  test "a QR of the config is produced for phone onboarding" do
    {:ok, _client, config} = Clients.enroll("phone")
    svg = Clients.qr_svg(config)

    assert svg =~ "<svg"
    assert String.length(svg) > 500
  end
end

defmodule Tunneld.OverlayTest do
  use ExUnit.Case, async: false

  alias Tunneld.Machines
  alias Tunneld.Overlay

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_overlay_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  test "address_for returns LAN IP for same-subnet machines" do
    # gateway is 192.168.1.1 in test config
    assert Overlay.address_for(%{"address" => "192.168.1.50"}) == "192.168.1.50"
  end

  test "address_for returns overlay IP for remote machines" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps", "address" => "203.0.113.5", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    ip = Overlay.address_for(m)
    assert ip =~ "10.88.0."
    refute ip == "203.0.113.5"
  end

  test "ensure_peer returns a stable overlay IP (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps2", "address" => "203.0.113.9", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    {:ok, %{overlay_ip: ip}} = Overlay.ensure_peer(m)
    {:ok, %{overlay_ip: ip2}} = Overlay.ensure_peer(m)
    assert ip == ip2
    assert ip =~ "10.88.0."
  end

  test "address_for is stable across calls for a remote machine" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps3", "address" => "203.0.113.10", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    assert Overlay.address_for(m) == Overlay.address_for(m)
  end

  test "remove_peer is idempotent (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps4", "address" => "203.0.113.11", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    _ = Overlay.ensure_peer(m)
    assert :ok = Overlay.remove_peer(m)
    assert :ok = Overlay.remove_peer(m)
  end

  test "status returns a map (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps5", "address" => "203.0.113.12", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    {:ok, st} = Overlay.status(m)
    assert st.interface == "wg-#{id}"
  end
end

defmodule Tunneld.ReconcileTest do
  use ExUnit.Case, async: false

  alias Tunneld.Machines
  alias Tunneld.Reconcile

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_reconcile_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")
    on_exit(fn -> File.rm_rf!(tmp); Application.put_env(:tunneld, :fs, root: prev_root) end)
    :ok
  end

  test "reconcile returns a subsystem map for a local machine (mock)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box", "address" => "192.168.1.5"})
    {:ok, m} = Machines.get(id)
    result = Reconcile.reconcile(m)
    assert Map.has_key?(result, :wireguard)
    assert Map.has_key?(result, :caddy)
    assert Map.has_key?(result, :ssh)
    assert Map.has_key?(result, :resources)
    assert result.wireguard == :ok  # local machines skip WG
    assert result.ssh == :ok
  end

  test "reconcile detects wireguard drift on a remote machine (mock)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps", "address" => "203.0.113.9", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    # mock Overlay.status returns up: false -> drift
    result = Reconcile.reconcile(m)
    assert result.wireguard == {:drift, :wireguard_down}
  end

  test "reconcile with repair calls Overlay.ensure_peer (mock returns ok)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps2", "address" => "203.0.113.10", "location" => "remote"})
    {:ok, m} = Machines.get(id)
    result = Reconcile.reconcile(m, repair: true)
    assert result.wireguard in [:ok, {:repaired, :wireguard}]
  end
end

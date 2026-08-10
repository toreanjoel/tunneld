defmodule Tunneld.MachinesTest do
  use ExUnit.Case, async: false

  alias Tunneld.Machines
  alias Tunneld.Machines.Store

  setup do
    # mock_data is on in test.exs, so SSH and Incus are simulated
    tmp = Path.join(System.tmp_dir!(), "tunneld_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  test "enroll creates a record, generates a keypair, and returns the public key" do
    {:ok, %{"id" => id, "public_key" => pub, "machine" => machine}} =
      Machines.enroll(%{"name" => "box1", "address" => "10.0.0.5"})

    assert String.starts_with?(pub, "ssh-ed25519 ")
    assert machine["name"] == "box1"
    assert machine["address"] == "10.0.0.5"
    assert machine["kind"] == "host"
    assert machine["status"] == "enrolled"
    assert is_nil(machine["capabilities"])

    assert {:ok, fetched} = Machines.get(id)
    assert fetched["id"] == id
  end

  test "enroll validates name and address" do
    assert {:error, "name is required"} = Machines.enroll(%{"address" => "10.0.0.5"})
    assert {:error, "address is required"} = Machines.enroll(%{"name" => "x"})
  end

  test "enroll infers location from the subnet and accepts explicit remote" do
    # Test gateway is 192.168.1.1, so 192.168.1.x is local, other ranges are remote.
    {:ok, %{"machine" => local}} =
      Machines.enroll(%{"name" => "loc1", "address" => "192.168.1.50"})

    assert local["location"] == "local"

    {:ok, %{"machine" => inferred_remote}} =
      Machines.enroll(%{"name" => "loc2", "address" => "10.0.0.5"})

    assert inferred_remote["location"] == "remote"

    {:ok, %{"machine" => explicit}} =
      Machines.enroll(%{"name" => "loc3", "address" => "192.168.1.60", "location" => "remote"})

    assert explicit["location"] == "remote"
  end

  test "infer_location returns local or remote based on the gateway subnet" do
    assert Machines.infer_location("192.168.1.42") == "local"
    assert Machines.infer_location("203.0.113.5") == "remote"
  end

  test "enroll rejects an invalid location" do
    assert {:error, "location must be local or remote"} =
             Machines.enroll(%{"name" => "x", "address" => "10.0.0.5", "location" => "cloud"})
  end

  test "probe fills generic capabilities and sets status ready (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box2", "address" => "10.0.0.6"})
    {:ok, machine} = Machines.probe(id)

    caps = machine["capabilities"]
    assert caps["os"] == "Ubuntu 24.04 LTS"
    assert caps["kernel"] == "6.8.0-31-generic"
    assert caps["arch"] == "x86_64"
    assert caps["cpu_count"] == 4
    assert caps["memory_mb"] == 8192
    assert is_list(caps["detected_runtimes"])
    assert machine["status"] == "ready"
    assert machine["last_seen"] != nil
  end

  test "remove deletes the record and key" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box4", "address" => "10.0.0.8"})
    assert :ok = Machines.remove(id)
    assert {:error, :not_found} = Machines.get(id)
  end

  test "Store round-trips records through atomic JSON" do
    :ok = Store.put(%{"id" => "x", "name" => "test", "address" => "1.2.3.4", "kind" => "incus"})
    {:ok, fetched} = Store.get("x")
    assert fetched["name"] == "test"
    :ok = Store.delete("x")
    assert {:error, :not_found} = Store.get("x")
  end

  test "probe on unknown id returns not_found" do
    assert {:error, :not_found} = Machines.probe("does-not-exist")
  end

  test "startup recovery probes enrolled machines to ready (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "recover1", "address" => "10.0.0.20"})

    # Freshly enrolled: no capabilities yet, status enrolled.
    {:ok, m} = Machines.get(id)
    assert m["status"] == "enrolled"
    assert is_nil(m["capabilities"])

    # recover_all probes every enrolled machine and fills capabilities.
    :ok = Machines.recover_all()

    {:ok, updated} = Machines.get(id)
    assert updated["status"] == "ready"
    assert updated["capabilities"]["arch"] == "x86_64"
  end
end

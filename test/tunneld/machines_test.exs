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
    assert machine["kind"] == "incus"
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
    {:ok, %{"machine" => local}} = Machines.enroll(%{"name" => "loc1", "address" => "192.168.1.50"})
    assert local["location"] == "local"

    {:ok, %{"machine" => inferred_remote}} = Machines.enroll(%{"name" => "loc2", "address" => "10.0.0.5"})
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

  test "probe fills capabilities and sets status ready (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box2", "address" => "10.0.0.6"})
    {:ok, machine} = Machines.probe(id)

    caps = machine["capabilities"]
    assert caps["provider"] == "incus"
    assert caps["incus_version"] == "Incus 6.0.0"
    assert caps["cpu_count"] == 4
    assert caps["memory_mb"] == 8192
    assert caps["kvm"] == true
    assert caps["gpu"] == false
    assert machine["status"] == "ready"
    assert machine["last_seen"] != nil
  end

  test "list_containers returns live state (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box3", "address" => "10.0.0.7"})
    {:ok, containers} = Machines.list_containers(id)

    names = Enum.map(containers, & &1["name"])
    assert "mock-app" in names
    assert "mock-vm" in names

    [app] = Enum.filter(containers, &(&1["name"] == "mock-app"))
    assert app["status"] == "Running"
    assert app["type"] == "container"
  end

  test "list_containers extracts IPv4 from the nested incus state.network structure" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box3b", "address" => "10.0.0.7"})
    {:ok, containers} = Machines.list_containers(id)

    [app] = Enum.filter(containers, &(&1["name"] == "mock-app"))
    assert app["ipv4"] == "10.10.0.42"

    [vm] = Enum.filter(containers, &(&1["name"] == "mock-vm"))
    assert vm["ipv4"] == ""
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

    # Starting a fresh Machines GenServer triggers the async startup recovery,
    # which probes every enrolled machine and fills capabilities.
    {:ok, _pid} = GenServer.start_link(Tunneld.Machines, %{}, name: :recovery_test)

    # Poll until the async recovery Task has updated the record.
    assert eventually(fn ->
             case Machines.get(id) do
               {:ok, %{"status" => "ready", "capabilities" => caps}} when not is_nil(caps) ->
                 caps["incus_version"] == "Incus 6.0.0"

               _ ->
                 false
             end
           end)
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts <= 0 -> false
      true ->
        Process.sleep(20)
        eventually(fun, attempts - 1)
    end
  end

  describe "container provisioning (mock)" do
    test "create_container provisions a new container visible in list" do
      {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "prov1", "address" => "10.0.0.10"})

      spec = %{
        "name" => "my-app",
        "image" => "ubuntu/24.04",
        "type" => "container",
        "cpu" => 2,
        "memory" => 1024,
        "ports" => [%{"host" => 8080, "container" => 80}]
      }

      {:ok, container} = Machines.create_container(id, spec)
      assert container["name"] == "my-app"
      assert container["status"] == "Running"

      {:ok, list} = Machines.list_containers(id)
      names = Enum.map(list, & &1["name"])
      assert "my-app" in names
    end

    test "create_container with vm type" do
      {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "prov2", "address" => "10.0.0.11"})

      {:ok, container} =
        Machines.create_container(id, %{
          "name" => "my-vm",
          "image" => "ubuntu/24.04",
          "type" => "vm"
        })

      assert container["type"] == "vm"
    end

    test "create_container validates spec" do
      {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "prov3", "address" => "10.0.0.12"})

      assert {:error, "name is required"} = Machines.create_container(id, %{"image" => "x"})
      assert {:error, "image is required"} = Machines.create_container(id, %{"name" => "x"})
      assert {:error, "type must be container or vm"} = Machines.create_container(id, %{"name" => "x", "image" => "y", "type" => "hyper-v"})
      assert {:error, "cpu must be a positive integer"} = Machines.create_container(id, %{"name" => "x", "image" => "y", "cpu" => 0})
    end

    test "start/stop/delete container lifecycle" do
      {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "prov4", "address" => "10.0.0.13"})
      {:ok, _} = Machines.create_container(id, %{"name" => "lifecycle", "image" => "ubuntu/24.04"})

      {:ok, stopped} = Machines.stop_container(id, "lifecycle")
      assert stopped["status"] == "Stopped"

      {:ok, started} = Machines.start_container(id, "lifecycle")
      assert started["status"] == "Running"

      {:ok, deleted} = Machines.delete_container(id, "lifecycle")
      assert deleted["status"] == "deleted"

      {:ok, list} = Machines.list_containers(id)
      refute Enum.any?(list, &(&1["name"] == "lifecycle"))
    end

    test "create_container with macvlan network" do
      {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "prov5", "address" => "10.0.0.14"})

      {:ok, container} =
        Machines.create_container(id, %{
          "name" => "macvlan-app",
          "image" => "ubuntu/24.04",
          "network" => "macvlan"
        })

      assert container["network"] == "macvlan"

      {:ok, list} = Machines.list_containers(id)
      assert Enum.any?(list, &(&1["name"] == "macvlan-app"))
    end

    test "create_container rejects macvlan for VMs" do
      {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "prov6", "address" => "10.0.0.15"})

      assert {:error, "macvlan networking is not supported for VMs"} =
               Machines.create_container(id, %{"name" => "vm", "image" => "x", "type" => "vm", "network" => "macvlan"})
    end

    test "create_container validates network" do
      {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "prov7", "address" => "10.0.0.16"})

      assert {:error, "network must be bridge or macvlan"} =
               Machines.create_container(id, %{"name" => "x", "image" => "y", "network" => "host"})
    end

    test "create_container on unknown machine returns not_found" do
      assert {:error, :not_found} = Machines.create_container("nope", %{"name" => "x", "image" => "y"})
    end
  end
end
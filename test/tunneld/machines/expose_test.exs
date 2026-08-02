defmodule Tunneld.Machines.ExposeTest do
  use ExUnit.Case, async: false

  alias Tunneld.Machines
  alias Tunneld.Machines.Expose
  alias Tunneld.Servers.Resources

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_expose_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  test "expose registers a resource and persists an exposure (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps", "address" => "203.0.113.9", "location" => "remote"})
    {:ok, _} = Machines.create_container(id, %{"name" => "web", "image" => "ubuntu/24.04"})

    {:ok, %{"name" => name, "lan_url" => lan_url, "local_port" => local_port}} =
      Expose.expose(id, "web", 8080)

    assert String.contains?(name, "vps")
    assert String.contains?(name, "web")
    assert is_integer(local_port)
    assert lan_url =~ name

    resources = Resources.fetch_shares()
    assert Enum.any?(resources, &(&1.name == name))
    assert Enum.any?(resources, &(&1.expose_source == "container" and &1.expose_machine_id == id))

    assert Enum.any?(Expose.list(), &(&1["machine_id"] == id and &1["container"] == "web"))
  end

  test "expose on unknown machine returns error" do
    assert {:error, :not_found} = Expose.expose("nope", "web", 8080)
  end

  defp wait_until(fun, tries \\ 20) do
    if tries == 0 do
      fun.()
    else
      if fun.() do
        true
      else
        Process.sleep(25)
        wait_until(fun, tries - 1)
      end
    end
  end

  test "unexpose removes the resource" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps2", "address" => "203.0.113.10", "location" => "remote"})
    {:ok, _} = Machines.create_container(id, %{"name" => "app", "image" => "ubuntu/24.04"})

    {:ok, %{"name" => name}} = Expose.expose(id, "app", 3000)
    assert Enum.any?(Resources.fetch_shares(), &(&1.name == name))

    Expose.unexpose(id, "app")

    assert wait_until(fn -> not Enum.any?(Resources.fetch_shares(), &(&1.name == name)) end)
    assert wait_until(fn -> not Enum.any?(Expose.list(), &(&1["container"] == "app")) end)
  end

  test "cleanup_machine removes all exposures for a machine" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps3", "address" => "203.0.113.11", "location" => "remote"})
    {:ok, _} = Machines.create_container(id, %{"name" => "a", "image" => "ubuntu/24.04"})
    {:ok, _} = Machines.create_container(id, %{"name" => "b", "image" => "ubuntu/24.04"})

    {:ok, %{"name" => na}} = Expose.expose(id, "a", 3001)
    {:ok, %{"name" => nb}} = Expose.expose(id, "b", 3002)

    Expose.cleanup_machine(id)

    assert wait_until(fn -> not Enum.any?(Resources.fetch_shares(), &(&1.name in [na, nb])) end)
    assert wait_until(fn -> not Enum.any?(Expose.list(), &(&1["machine_id"] == id)) end)
  end

  test "deleting a container cleans up its exposure" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "vps4", "address" => "203.0.113.12", "location" => "remote"})
    {:ok, _} = Machines.create_container(id, %{"name" => "app", "image" => "ubuntu/24.04"})

    {:ok, %{"name" => name}} = Expose.expose(id, "app", 4000)
    assert Enum.any?(Resources.fetch_shares(), &(&1.name == name))

    {:ok, _} = Machines.delete_container(id, "app")

    assert wait_until(fn -> not Enum.any?(Resources.fetch_shares(), &(&1.name == name)) end)
    assert wait_until(fn -> not Enum.any?(Expose.list(), &(&1["container"] == "app")) end)
  end
end

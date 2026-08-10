defmodule Tunneld.Machines.RuntimeTest do
  use ExUnit.Case, async: false

  alias Tunneld.Machines
  alias Tunneld.Machines.Runtime

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_runtime_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  test "listeners parses ss output and annotates containers (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box", "address" => "10.0.0.5"})
    {:ok, listeners} = Machines.listeners(id)

    ssh = Enum.find(listeners, &(&1["port"] == 22))
    assert ssh["proc"] == "sshd"
    assert ssh["pid"] == 1234
    assert ssh["addr"] == "0.0.0.0"

    node = Enum.find(listeners, &(&1["port"] == 8080))
    assert node["proc"] == "node"
    assert node["pid"] == 5678
    assert node["container"] == nil
  end

  test "probe returns generic capabilities with detected_runtimes (mock mode)" do
    {:ok, %{"id" => id}} = Machines.enroll(%{"name" => "box2", "address" => "10.0.0.6"})
    {:ok, machine} = Machines.get(id)
    {:ok, caps} = Runtime.probe(machine)

    assert caps["os"] == "Ubuntu 24.04 LTS"
    assert caps["kernel"] == "6.8.0-31-generic"
    assert caps["arch"] == "x86_64"
    assert caps["cpu_count"] == 4
    assert caps["memory_mb"] == 8192
    assert is_list(caps["detected_runtimes"])
  end

  test "listeners on unknown machine returns not_found" do
    assert {:error, :not_found} = Machines.listeners("does-not-exist")
  end
end

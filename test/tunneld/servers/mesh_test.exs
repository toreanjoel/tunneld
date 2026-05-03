defmodule Tunneld.Servers.MeshTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Mesh

  setup_all do
    for f <- ["mesh_config.json", "mesh_config.json.bak", "mesh_node_id.json"] do
      Path.join(Tunneld.Config.fs_root(), f) |> File.rm_rf()
    end

    Application.put_env(:tunneld, :mesh,
      enabled: false,
      coordinator_url: nil,
      token: nil,
      node_name: "",
      poll_interval: 25_000
    )

    Mesh.reconfigure()
    Process.sleep(1000)

    :ok
  end

  setup do
    path = Path.join(Tunneld.Config.fs_root(), "mesh_config.json")
    File.rm_rf(path)
    File.rm_rf(path <> ".bak")

    Application.put_env(:tunneld, :mesh,
      enabled: false,
      coordinator_url: nil,
      token: nil,
      node_name: "",
      poll_interval: 25_000
    )

    Mesh.reconfigure()
    Process.sleep(1000)

    on_exit(fn ->
      File.rm_rf(path)
      File.rm_rf(path <> ".bak")
      Application.put_env(:tunneld, :mesh,
        enabled: false,
        coordinator_url: nil,
        token: nil,
        node_name: "",
        poll_interval: 25_000
      )
      Mesh.reconfigure()
      Process.sleep(500)
    end)

    :ok
  end

  test "get_state returns disabled when mesh is not configured" do
    state = Mesh.get_state()
    assert state.enabled == false
  end

  test "reconfigure reads persisted config and updates state" do
    path = Path.join(Tunneld.Config.fs_root(), "mesh_config.json")

    Tunneld.Persistence.write_json(path, %{
      "coordinator_url" => "http://relay.test:4000",
      "token" => "secret",
      "node_name" => "test-node",
      "enabled" => true
    })

    Application.put_env(:tunneld, :mesh,
      coordinator_url: "http://relay.test:4000",
      token: "secret",
      node_name: "test-node",
      enabled: true,
      poll_interval: 25_000
    )

    :ok = Mesh.reconfigure()
    Process.sleep(100)

    state = Mesh.get_state()
    assert state.enabled == true
    assert state.coordinator_url == "http://relay.test:4000"
    assert state.node_name == "test-node"
  end

  test "reconfigure disables mesh when config is cleared" do
    path = Path.join(Tunneld.Config.fs_root(), "mesh_config.json")

    # First enable
    Tunneld.Persistence.write_json(path, %{
      "coordinator_url" => "http://relay.test:4000",
      "token" => "secret",
      "node_name" => "test-node",
      "enabled" => true
    })

    Application.put_env(:tunneld, :mesh,
      coordinator_url: "http://relay.test:4000",
      token: "secret",
      node_name: "test-node",
      enabled: true,
      poll_interval: 25_000
    )

    :ok = Mesh.reconfigure()
    Process.sleep(100)

    assert Mesh.get_state().enabled == true

    # Now disable
    Tunneld.Persistence.write_json(path, %{
      "coordinator_url" => "",
      "token" => "",
      "node_name" => "",
      "enabled" => false
    })

    Application.put_env(:tunneld, :mesh,
      enabled: false,
      coordinator_url: nil,
      token: nil,
      node_name: "",
      poll_interval: 25_000
    )

    :ok = Mesh.reconfigure()
    Process.sleep(100)

    state = Mesh.get_state()
    assert state.enabled == false
  end
end

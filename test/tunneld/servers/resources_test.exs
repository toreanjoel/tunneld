defmodule Tunneld.Servers.ResourcesTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Resources

  setup do
    # Point fs config to a temp directory for isolation
    tmp_dir = System.tmp_dir!() |> Path.join("tunneld_resources_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    original_fs = Application.get_env(:tunneld, :fs)
    Application.put_env(:tunneld, :fs, Keyword.merge(original_fs, root: tmp_dir))

    on_exit(fn ->
      Application.put_env(:tunneld, :fs, original_fs)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "path/0" do
    test "returns a path ending in resources.json" do
      path = Resources.path()
      assert is_binary(path)
      assert String.ends_with?(path, "resources.json")
    end
  end

  describe "file_exists?/0 and create_file/0" do
    test "file does not exist initially", %{tmp_dir: _} do
      refute Resources.file_exists?()
    end

    test "create_file creates the resources file", %{tmp_dir: _} do
      assert {:ok, _} = Resources.create_file()
      assert Resources.file_exists?()
    end

    test "created file contains empty JSON array", %{tmp_dir: _} do
      Resources.create_file()
      data = Resources.read_file()
      assert data == []
    end
  end

  describe "read_file/0" do
    test "returns empty list when file does not exist", %{tmp_dir: _} do
      assert Resources.read_file() == []
    end

    test "reads valid JSON array", %{tmp_dir: _} do
      Resources.create_file()
      data = Resources.read_file()
      assert is_list(data)
    end

    test "reads resources written to the file", %{tmp_dir: _} do
      resource = %{
        "id" => "test1",
        "name" => "testapp",
        "kind" => "host",
        "ip" => "127.0.0.1",
        "port" => "18000",
        "pool" => ["10.0.0.5:3000"],
        "description" => "test resource",
        "tunneld" => %{}
      }

      File.write!(Resources.path(), Jason.encode!([resource]))
      data = Resources.read_file()
      assert length(data) == 1
      assert hd(data)["name"] == "testapp"
    end
  end

  describe "fetch_shares/0" do
    test "returns empty list when no resources exist", %{tmp_dir: _} do
      Resources.create_file()
      shares = Resources.fetch_shares()
      assert shares == []
    end

    test "maps resource fields to atom-keyed maps", %{tmp_dir: _} do
      resource = %{
        "id" => "res1",
        "name" => "myapp",
        "kind" => "host",
        "ip" => "127.0.0.1",
        "port" => "18000",
        "pool" => ["10.0.0.5:3000"],
        "description" => "my test app",
        "tunneld" => %{"enabled" => %{}}
      }

      File.write!(Resources.path(), Jason.encode!([resource]))
      [share] = Resources.fetch_shares()

      assert share.id == "res1"
      assert share.name == "myapp"
      assert share.kind == "host"
      assert share.ip == "127.0.0.1"
      assert share.port == "18000"
      assert share.pool == ["10.0.0.5:3000"]
      assert share.description == "my test app"
      assert is_map(share.health)
    end

    test "access kind parses bind address", %{tmp_dir: _} do
      resource = %{
        "id" => "acc1",
        "name" => "remote-service",
        "kind" => "access",
        "bind" => "0.0.0.0:9090",
        "description" => "remote access",
        "tunneld" => %{}
      }

      File.write!(Resources.path(), Jason.encode!([resource]))
      [share] = Resources.fetch_shares()

      assert share.kind == "access"
      assert share.ip == "0.0.0.0"
      assert share.port == "9090"
      assert share.health == %{status: :not_applicable}
    end

    test "defaults to host kind when not specified", %{tmp_dir: _} do
      resource = %{
        "id" => "x1",
        "name" => "notkind",
        "ip" => "127.0.0.1",
        "port" => "18000",
        "pool" => [],
        "tunneld" => %{}
      }

      File.write!(Resources.path(), Jason.encode!([resource]))
      [share] = Resources.fetch_shares()

      assert share.kind == "host"
    end
  end
end

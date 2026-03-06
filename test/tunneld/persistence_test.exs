defmodule Tunneld.PersistenceTest do
  use ExUnit.Case, async: true

  alias Tunneld.Persistence

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("tunneld_persist_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{dir: tmp_dir}
  end

  describe "write_json/2 and read_json/1" do
    test "round-trips data", %{dir: dir} do
      path = Path.join(dir, "test.json")
      data = %{"key" => "value", "list" => [1, 2, 3]}

      assert :ok = Persistence.write_json(path, data)
      assert {:ok, ^data} = Persistence.read_json(path)
    end

    test "creates backup file on write", %{dir: dir} do
      path = Path.join(dir, "test.json")

      Persistence.write_json(path, %{"v" => 1})
      Persistence.write_json(path, %{"v" => 2})

      assert File.exists?(path <> ".bak")
      {:ok, backup} = Jason.decode(File.read!(path <> ".bak"))
      assert backup["v"] == 1
    end

    test "recovers from corrupted main file using backup", %{dir: dir} do
      path = Path.join(dir, "test.json")

      Persistence.write_json(path, %{"original" => true})
      Persistence.write_json(path, %{"updated" => true})

      # Corrupt the main file
      File.write!(path, "not valid json{{{")

      # Should fall back to backup
      {:ok, data} = Persistence.read_json(path)
      assert data["original"] == true
    end

    test "returns error when neither file nor backup exists", %{dir: dir} do
      path = Path.join(dir, "nonexistent.json")
      assert {:error, _} = Persistence.read_json(path)
    end
  end

  describe "write_json/2 error handling" do
    test "returns error for invalid path" do
      assert {:error, _} = Persistence.write_json("/nonexistent/dir/file.json", %{})
    end
  end
end

defmodule Tunneld.ConfigTest do
  use ExUnit.Case, async: false

  alias Tunneld.Config

  setup do
    original_fs = Application.get_env(:tunneld, :fs)

    on_exit(fn ->
      Application.put_env(:tunneld, :fs, original_fs)
    end)

    :ok
  end

  describe "fs/1" do
    test "reads from keyword list config" do
      Application.put_env(:tunneld, :fs, root: "/test/path", auth: "auth.json")
      assert Config.fs(:root) == "/test/path"
      assert Config.fs(:auth) == "auth.json"
    end

    test "reads from map config with atom keys" do
      Application.put_env(:tunneld, :fs, %{root: "/map/path", auth: "auth.json"})
      assert Config.fs(:root) == "/map/path"
    end

    test "reads from map config with string keys" do
      Application.put_env(:tunneld, :fs, %{"root" => "/string/path"})
      assert Config.fs(:root) == "/string/path"
    end

    test "returns nil for missing key" do
      Application.put_env(:tunneld, :fs, root: "/path")
      assert Config.fs(:nonexistent) == nil
    end

    test "returns nil when fs config is nil" do
      Application.put_env(:tunneld, :fs, nil)
      assert Config.fs(:root) == nil
    end
  end

  describe "fs_root/0" do
    test "returns configured root" do
      Application.put_env(:tunneld, :fs, root: "/custom/root")
      assert Config.fs_root() == "/custom/root"
    end

    test "returns default when root not configured" do
      Application.put_env(:tunneld, :fs, nil)
      assert Config.fs_root() == "/var/lib/tunneld"
    end
  end
end

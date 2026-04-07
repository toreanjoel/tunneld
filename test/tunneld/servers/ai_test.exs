defmodule Tunneld.Servers.AiTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Ai

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "tunneld_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    original_fs = Application.get_env(:tunneld, :fs)
    original_mock = Application.get_env(:tunneld, :mock_data)
    Application.put_env(:tunneld, :fs, root: tmp_dir, auth: "auth.json", ai: "ai.json")
    Application.put_env(:tunneld, :mock_data, false)

    on_exit(fn ->
      Application.put_env(:tunneld, :fs, original_fs)
      Application.put_env(:tunneld, :mock_data, original_mock)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "configured?/0" do
    test "returns false when no config file exists" do
      refute Ai.configured?()
    end

    test "returns true after saving valid config" do
      Ai.save_config(%{"base_url" => "http://localhost:11434/v1", "model" => "llama3"})
      assert Ai.configured?()
    end
  end

  describe "save_config/1" do
    test "saves and round-trips through read_config" do
      config = %{"base_url" => "http://localhost:11434/v1", "api_key" => "sk-test", "model" => "llama3"}
      assert {:ok, saved} = Ai.save_config(config)
      assert saved["base_url"] == "http://localhost:11434/v1"
      assert saved["api_key"] == "sk-test"
      assert saved["model"] == "llama3"

      assert {:ok, read} = Ai.read_config()
      assert read == saved
    end

    test "rejects empty base_url" do
      assert {:error, "base_url cannot be empty"} = Ai.save_config(%{"base_url" => ""})
    end

    test "rejects whitespace-only base_url" do
      assert {:error, "base_url cannot be empty"} = Ai.save_config(%{"base_url" => "  "})
    end

    test "rejects missing base_url" do
      assert {:error, "base_url is required"} = Ai.save_config(%{"model" => "llama3"})
    end

    test "defaults api_key and model to empty strings" do
      assert {:ok, saved} = Ai.save_config(%{"base_url" => "http://localhost:11434/v1"})
      assert saved["api_key"] == ""
      assert saved["model"] == ""
    end
  end

  describe "read_config/0" do
    test "returns error when no file exists" do
      assert {:error, _} = Ai.read_config()
    end
  end

  describe "clear_config/0" do
    test "removes the config file" do
      Ai.save_config(%{"base_url" => "http://localhost:11434/v1", "model" => "llama3"})
      assert Ai.configured?()

      assert :ok = Ai.clear_config()
      refute Ai.configured?()
    end

    test "succeeds when no file exists" do
      assert :ok = Ai.clear_config()
    end
  end

  describe "path/0" do
    test "returns path ending in ai.json" do
      assert String.ends_with?(Ai.path(), "ai.json")
    end
  end
end

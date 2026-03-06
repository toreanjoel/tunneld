defmodule Tunneld.Servers.SqmTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Sqm

  describe "get_state/0" do
    test "returns current SQM state with expected keys" do
      state = Sqm.get_state()
      assert is_map(state)
      assert Map.has_key?(state, "mode")
      assert Map.has_key?(state, "up_limit")
      assert Map.has_key?(state, "down_limit")
    end
  end

  describe "set_sqm/1 in mock mode" do
    test "updates SQM settings" do
      original_state = Sqm.get_state()

      assert :ok = Sqm.set_sqm(%{"mode" => "balanced", "up_limit" => "40mbit", "down_limit" => "20mbit"})

      state = Sqm.get_state()
      assert state["mode"] == "balanced"
      assert state["up_limit"] == "40mbit"
      assert state["down_limit"] == "20mbit"

      # Restore original state
      Sqm.set_sqm(original_state)
    end

    test "turning off resets mode" do
      Sqm.set_sqm(%{"mode" => "balanced", "up_limit" => "40mbit", "down_limit" => "20mbit"})
      assert :ok = Sqm.set_sqm(%{"mode" => "off"})
      assert Sqm.get_state()["mode"] == "off"
    end
  end

  describe "path/0" do
    test "returns a path ending in sqm.json" do
      path = Sqm.path()
      assert is_binary(path)
      assert String.ends_with?(path, "sqm.json")
    end
  end

  describe "file_exists?/0" do
    test "returns a boolean" do
      assert is_boolean(Sqm.file_exists?())
    end
  end
end

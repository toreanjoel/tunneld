defmodule Tunneld.Servers.ResourcesTest.HealthTest do
  use ExUnit.Case, async: true

  alias Tunneld.Servers.Resources

  describe "pool_health/2 in mock mode" do
    test "returns partial status with one down entry" do
      result = Resources.pool_health(["192.168.1.1:8080", "192.168.1.2:8080"], true)
      assert result.status == :partial
      assert result.total == 2
      assert result.up == 1
    end

    test "returns empty for empty pool in mock mode" do
      result = Resources.pool_health([], true)
      assert result.status == :all_up
      assert result.total == 0
    end
  end

  describe "pool_health/2 in live mode" do
    test "returns empty for empty pool" do
      result = Resources.pool_health([], false)
      assert result.status == :empty
      assert result.total == 0
      assert result.up == 0
    end

    test "returns none when no backends are reachable" do
      result = Resources.pool_health(["192.0.2.1:9999"], false)
      assert result.status == :none
      assert result.total == 1
      assert result.up == 0
    end

    test "skips entries with invalid port" do
      result = Resources.pool_health(["192.168.1.1:abc"], false)
      assert result.total == 1
      assert result.up == 0
    end

    test "skips malformed entries" do
      result = Resources.pool_health(["not-a-valid-entry"], false)
      assert result.total == 0
    end

    test "trims whitespace from entries" do
      result = Resources.pool_health(["  192.0.2.1:9999  "], false)
      assert result.total == 1
    end

    test "filters empty strings" do
      result = Resources.pool_health(["", "  ", "192.0.2.1:9999"], false)
      assert result.total == 1
    end
  end

  describe "pool_health/2 edge cases" do
    test "returns empty for non-list pool" do
      assert Resources.pool_health(nil, false) == %{status: :empty, total: 0, up: 0}
      assert Resources.pool_health("not a list", true) == %{status: :empty, total: 0, up: 0}
    end
  end
end
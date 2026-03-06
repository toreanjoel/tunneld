defmodule Tunneld.Servers.Resources.HealthTest do
  use ExUnit.Case, async: true

  alias Tunneld.Servers.Resources.Health

  describe "pool_health/2 in mock mode" do
    test "returns mock status with pool count" do
      result = Health.pool_health(["192.168.1.1:8080", "192.168.1.2:8080"], true)
      assert result.status == :mock
      assert result.total == 2
      assert result.up == nil
    end

    test "returns mock status for empty pool" do
      result = Health.pool_health([], true)
      assert result.status == :mock
      assert result.total == 0
    end
  end

  describe "pool_health/2 in live mode" do
    test "returns empty for empty pool" do
      result = Health.pool_health([], false)
      assert result.status == :empty
      assert result.total == 0
      assert result.up == 0
    end

    test "returns none when no backends are reachable" do
      # Use a non-routable IP to ensure connection fails quickly
      result = Health.pool_health(["192.0.2.1:9999"], false)
      assert result.status == :none
      assert result.total == 1
      assert result.up == 0
    end

    test "skips entries with invalid port" do
      result = Health.pool_health(["192.168.1.1:abc"], false)
      assert result.total == 1
      assert result.up == 0
    end

    test "skips malformed entries" do
      result = Health.pool_health(["not-a-valid-entry"], false)
      assert result.total == 0
    end

    test "trims whitespace from entries" do
      result = Health.pool_health(["  192.0.2.1:9999  "], false)
      assert result.total == 1
    end

    test "filters empty strings" do
      result = Health.pool_health(["", "  ", "192.0.2.1:9999"], false)
      assert result.total == 1
    end
  end

  describe "pool_health/2 edge cases" do
    test "returns empty for non-list pool" do
      assert Health.pool_health(nil, false) == %{status: :empty, total: 0, up: 0}
      assert Health.pool_health("not a list", true) == %{status: :empty, total: 0, up: 0}
    end
  end
end

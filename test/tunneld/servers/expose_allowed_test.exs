defmodule Tunneld.Servers.ExposeAllowedTest do
  use ExUnit.Case, async: true
  alias Tunneld.Servers.ExposeAllowed

  @mac "aa:bb:cc:dd:ee:ff"
  @mac2 "11:22:33:44:55:66"

  setup do
    path = Path.join(Tunneld.Config.fs_root(), "expose_allowed.json")
    File.rm(path)
    File.rm(path <> ".bak")
    :ok
  end

  test "allowed?/1 returns false when file missing" do
    refute ExposeAllowed.allowed?(@mac)
  end

  test "allow/1 then allowed?/1 returns true" do
    assert :ok = ExposeAllowed.allow(@mac)
    assert ExposeAllowed.allowed?(@mac)
    refute ExposeAllowed.allowed?(@mac2)
  end

  test "revoke/1 then allowed?/1 returns false" do
    assert :ok = ExposeAllowed.allow(@mac)
    assert ExposeAllowed.allowed?(@mac)
    assert :ok = ExposeAllowed.revoke(@mac)
    refute ExposeAllowed.allowed?(@mac)
  end

  test "multiple macs are tracked independently" do
    assert :ok = ExposeAllowed.allow(@mac)
    assert :ok = ExposeAllowed.allow(@mac2)
    assert ExposeAllowed.allowed?(@mac)
    assert ExposeAllowed.allowed?(@mac2)

    assert :ok = ExposeAllowed.revoke(@mac)
    refute ExposeAllowed.allowed?(@mac)
    assert ExposeAllowed.allowed?(@mac2)
  end
end

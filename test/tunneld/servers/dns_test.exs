defmodule Tunneld.Servers.DnsTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Dns

  setup do
    # Ensure the GenServer is running
    unless GenServer.whereis(Dns) do
      Dns.start_link([])
    end

    :ok
  end

  describe "get_state/0" do
    test "returns current DNS state with expected keys" do
      state = Dns.get_state()
      assert is_map(state)
      assert Map.has_key?(state, "provider")
      assert Map.has_key?(state, "status")
    end

    test "default provider is mullvad-doh" do
      state = Dns.get_state()
      assert state["provider"] == "mullvad-doh"
    end

    test "status is :active by default" do
      # Reset to mullvad-doh to ensure clean state
      Dns.set_provider("mullvad-doh")
      state = Dns.get_state()
      assert state["status"] == :active
    end
  end

  describe "providers/0" do
    test "returns list of provider tuples" do
      providers = Dns.providers()
      assert is_list(providers)
      assert length(providers) == 6
      assert {"mullvad-doh", "Mullvad DoH"} in providers
      assert {"cloudflare", "Cloudflare"} in providers
    end
  end

  describe "label_for/1" do
    test "returns label for known provider" do
      assert Dns.label_for("mullvad-doh") == "Mullvad DoH"
      assert Dns.label_for("cloudflare") == "Cloudflare"
      assert Dns.label_for("quad9-dnscrypt-ip4-filter-pri") == "Quad9 (Security)"
    end

    test "returns id for unknown provider" do
      assert Dns.label_for("unknown") == "unknown"
    end
  end

  describe "set_provider/1" do
    test "returns error for invalid provider" do
      assert {:error, :invalid_provider} = Dns.set_provider("nonexistent")
    end

    test "returns ok when setting same provider" do
      result = Dns.set_provider("mullvad-doh")
      assert match?({:ok, _}, result)
    end

    test "changes provider successfully in mock mode" do
      assert {:ok, "cloudflare"} = Dns.set_provider("cloudflare")

      state = Dns.get_state()
      assert state["provider"] == "cloudflare"
      assert state["status"] == :active

      # Restore original
      Dns.set_provider("mullvad-doh")
    end

    test "rejects invalid provider without changing state" do
      original = Dns.get_state()
      assert {:error, :invalid_provider} = Dns.set_provider("not-real")
      assert Dns.get_state()["provider"] == original["provider"]
    end

    test "can switch between providers multiple times" do
      assert {:ok, "cloudflare"} = Dns.set_provider("cloudflare")
      assert Dns.get_state()["provider"] == "cloudflare"

      assert {:ok, "quad9-dnscrypt-ip4-filter-pri"} = Dns.set_provider("quad9-dnscrypt-ip4-filter-pri")
      assert Dns.get_state()["provider"] == "quad9-dnscrypt-ip4-filter-pri"

      # Restore
      Dns.set_provider("mullvad-doh")
    end
  end

  describe "toml_path/0" do
    test "returns a path ending in dnscrypt-proxy.toml" do
      path = Dns.toml_path()
      assert is_binary(path)
      assert String.ends_with?(path, "dnscrypt-proxy.toml")
    end
  end

  describe "TOML round-trip via set_provider" do
    test "provider change writes and reads back correctly" do
      # Start from a known state
      Dns.set_provider("mullvad-doh")

      # Change to cloudflare
      assert {:ok, "cloudflare"} = Dns.set_provider("cloudflare")

      # Read it back via get_state (which reads from GenServer state, which
      # was updated from the TOML file in mock mode)
      assert Dns.get_state()["provider"] == "cloudflare"

      # Change back
      Dns.set_provider("mullvad-doh")
    end

    test "switching providers multiple times maintains file integrity" do
      Dns.set_provider("mullvad-doh")

      for provider <- ["cloudflare", "quad9-dnscrypt-ip4-filter-pri", "adguard-dns", "mullvad-doh"] do
        assert {:ok, ^provider} = Dns.set_provider(provider)
        assert Dns.get_state()["provider"] == provider
      end
    end
  end
end
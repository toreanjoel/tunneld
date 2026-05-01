defmodule Tunneld.Servers.DnsConfigTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.DnsConfig

  setup do
    unless Process.whereis(DnsConfig), do: DnsConfig.start_link([])
    :ok
  end

  describe "get_dns_server/0" do
    test "returns a valid IP string" do
      server = DnsConfig.get_dns_server()
      assert is_binary(server)
      assert String.match?(server, ~r/^\d+\.\d+\.\d+\.\d+$/)
    end
  end

  describe "set_dns_server/1" do
    test "persists and returns new DNS server IP" do
      assert :ok = DnsConfig.set_dns_server("8.8.8.8")
      assert DnsConfig.get_dns_server() == "8.8.8.8"
    end
  end
end

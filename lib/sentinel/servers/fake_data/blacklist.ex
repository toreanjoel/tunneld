defmodule Sentinel.Servers.FakeData.Blacklist do
  @moduledoc """
  Fake data for blacklist
  """
  def get_data() do
    [
      %{
        "domain" => "facebook.com",
        "ip" => "102.132.99.35",
        "mac_addr" => "123",
        "ttl" => "-",
        "type" => "system"
      },
      %{
        "domain" => "example.com",
        "ip" => "23.215.0.138",
        "mac_addr" => "111",
        "ttl" => "-",
        "type" => "system"
      },
      %{
        "domain" => "example.com",
        "ip" => "96.7.128.198",
        "mac_addr" => "111",
        "ttl" => "-",
        "type" => "system"
      },
      %{
        "domain" => "example.com",
        "ip" => "23.215.0.136",
        "mac_addr" => "111",
        "ttl" => "-",
        "type" => "system"
      },
      %{
        "domain" => "example.com",
        "ip" => "23.192.228.84",
        "mac_addr" => "111",
        "ttl" => "-",
        "type" => "system"
      },
      %{
        "domain" => "example.com",
        "ip" => "23.192.228.80",
        "mac_addr" => "111",
        "ttl" => "-",
        "type" => "system"
      },
      %{
        "type" => "system",
        "ttl" => "-",
        "domain" => "example.com",
        "ip" => "96.7.128.175",
        "mac_addr" => "111"
      }
    ]
  end
end

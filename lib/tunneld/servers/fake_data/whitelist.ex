defmodule Tunneld.Servers.FakeData.Whitelist do
  @moduledoc """
  Fake data for Whitelist
  """
  def get_data() do
    [
      %{
        "hostname" => "DEVICE ONE",
        "ip" => "102.132.99.35",
        "mac" => "123",
        "ttl" => "-",
        "status" => "PENDING"
      },
      %{
        "hostname" => "DEVICE TWO",
        "ip" => "102.132.99.34",
        "mac" => "1234",
        "ttl" => "-",
        "status" => "PENDING"
      },
      %{
        "hostname" => "DEVICE THREE",
        "ip" => "102.132.99.35",
        "mac" => "12345",
        "ttl" => "-",
        "status" => "GRANTED"
      },
      %{
        "hostname" => "DEVICE FOUR",
        "ip" => "102.132.99.35",
        "mac" => "123456",
        "ttl" => "1739977639",
        "status" => "GRANTED"
      }
    ]
  end
end

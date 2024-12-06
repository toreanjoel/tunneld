defmodule Sentinel.Servers.FakeData.Blacklist do
  @moduledoc """
  Fake data for blacklist
  """
  def get_data() do
    [
      "local=/item.1.com",
      "local=/item.2.com",
      "local=/item.3.com",
      "local=/item.4.com",
      "local=/item.5.com",
    ]
  end
end

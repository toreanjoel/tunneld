defmodule Sentinel.Servers.FakeData.Logs do
  @moduledoc """
  Fake data for Logs
  """
  def get_data() do
    [
      %{
        domain: "connectivitycheck.gstatic.com",
        ip: "10.0.0.94",
        query_type: "A",
        time: "Nov 29 22:32:16"
      },
      %{
        domain: "www.google.com",
        ip: "10.0.0.94",
        query_type: "A",
        time: "Nov 29 22:32:16"
      },
      %{
        domain: "mtalk.google.com",
        ip: "10.0.0.33",
        query_type: "A",
        time: "Nov 29 22:32:17"
      },
      %{
        domain: "2.android.pool.ntp.org",
        ip: "10.0.0.33",
        query_type: "A",
        time: "Nov 29 22:32:17"
      },
      %{
        domain: "roughtime.int08h.com",
        ip: "10.0.0.33",
        query_type: "A",
        time: "Nov 29 22:32:17"
      },
      %{
        domain: "www.samsung.com",
        ip: "10.0.0.33",
        query_type: "A",
        time: "Nov 29 22:32:17"
      },
      %{
        domain: "www.google.com",
        ip: "10.0.0.33",
        query_type: "A",
        time: "Nov 29 22:32:17"
      },
      %{
        domain: "www.tizen.org",
        ip: "10.0.0.94",
        query_type: "A",
        time: "Nov 29 22:32:18"
      },
      %{
        domain: "www.samsungknox.com",
        ip: "10.0.0.94",
        query_type: "A",
        time: "Nov 29 22:32:18"
      }
    ]
  end
end

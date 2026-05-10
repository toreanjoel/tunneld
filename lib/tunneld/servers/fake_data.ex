defmodule Tunneld.Servers.FakeData do
  @moduledoc """
  Fake data for development/testing when mock_data is enabled.
  """

  @doc "Fake DHCP lease data for connected devices."
  def devices do
    {
      "1732984082 b2:11:11:11:11:11 10.0.0.59 Person1Person1Person1Person1 01:11:11:11:11:11:11\n1732995766 22:22:22:22:22:20 10.0.0.33 Person2 22:22:22:22:22:22:20\n",
      0}
  end

  @doc "Fake mesh state with connected peers."
  def mesh do
    %{
      status: :connected,
      coordinator_url: "http://relay.example.com:4000",
      token: "fake-token",
      node_name: "mock-gateway",
      mesh_ip: "10.0.0.2",
      relay_endpoint: "139.84.227.63:51820",
      relay_pubkey: "cz7L+YZiThnl+kul8SyrEKsp94zry3QBGVMwl8c3g3o=",
      peers: %{
        "peer1Pubkey" => %{
          "node_id" => "node-office",
          "name" => "Office Gateway",
          "mesh_ip" => "10.0.0.3",
          "allowed_ips" => ["192.168.10.0/24"],
          "last_seen" => System.os_time(:millisecond),
          "public_ip" => "203.0.113.1",
          "country_code" => "US",
          "country_name" => "United States",
          "latitude" => 37.7749,
          "longitude" => -122.4194
        },
        "peer2Pubkey" => %{
          "node_id" => "node-home",
          "name" => "Home Gateway",
          "mesh_ip" => "10.0.0.4",
          "allowed_ips" => ["192.168.1.0/24"],
          "last_seen" => System.os_time(:millisecond),
          "public_ip" => "198.51.100.5",
          "country_code" => "GB",
          "country_name" => "United Kingdom",
          "latitude" => 51.5074,
          "longitude" => -0.1278
        }
      },
      last_sync: DateTime.utc_now()
    }
  end

  @doc "Fake Wi-Fi scan results."
  def wlan do
    [
      %{
        open: false,
        security: "[WPA2-PSK-CCMP][WPS][ESS]",
        signal: "-58",
        ssid: "JS_5G"
      },
      %{open: false, security: "[WPA2-PSK-CCMP][ESS]", signal: "-32", ssid: ""},
      %{
        open: false,
        security: "[WPA2-PSK-CCMP][ESS]",
        signal: "-33",
        ssid: "tunneld.local_5G"
      },
      %{
        open: false,
        security: "[WPA2-PSK-CCMP][WPS][ESS]",
        signal: "-58",
        ssid: "JS"
      }
    ]
  end
end
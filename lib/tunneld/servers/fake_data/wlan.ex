defmodule Tunneld.Servers.FakeData.Wlan do
  @moduledoc """
  Fake data for Wlan
  """
  def get_data() do
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

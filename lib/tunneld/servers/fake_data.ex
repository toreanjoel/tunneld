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
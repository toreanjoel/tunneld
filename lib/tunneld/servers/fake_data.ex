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

  @doc "Fake DNS blocklist metadata."
  def blocklist do
    %{
      "description" =>
        "Big broom - Cleans the Internet and protects your privacy! Blocks Ads, Affiliate, Tracking, Metrics, Telemetry, Phishing, Malware, Scam, Fake, Crytojacking and other \"Crap\".",
      "disclaimer" => "https://github.com/hagezi/dns-blocklists/blob/main/README.md#disclaimer",
      "expires" => "1 day",
      "homepage" => "https://github.com/hagezi/dns-blocklists",
      "issues" => "https://github.com/hagezi/dns-blocklists/issues",
      "last modified" => "16 Nov 2025 14:07 UTC",
      "license" => "https://github.com/hagezi/dns-blocklists/blob/main/LICENSE",
      "number of entries" => "175470",
      "syntax" => "DNSMasq v2.86 or newer",
      "title" => "HaGeZi's Pro DNS Blocklist",
      "version" => "2025.1116.1407.10"
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
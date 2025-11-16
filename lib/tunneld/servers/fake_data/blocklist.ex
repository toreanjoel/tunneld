defmodule Tunneld.Servers.FakeData.Blocklist do
  @moduledoc """
  Fake data for blicklist
  """
  def get_data() do
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
end

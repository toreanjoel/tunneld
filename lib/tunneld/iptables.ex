defmodule Tunneld.Iptables do
  @moduledoc """
  Configures iptables firewall rules for the Tunneld gateway.

  On startup (production only), flushes all existing rules and sets up:
  - IP forwarding between ethernet and WiFi interfaces
  - NAT masquerading for internet access via WiFi and VPN (Mullvad)
  - DNS redirection: all port-53 traffic is redirected to port 5336
    (where dnscrypt-proxy listens) to enforce encrypted DNS
  - Gateway access rules allowing devices to reach the Tunneld host

  This module is called once at application start and is not a GenServer.
  """

  @doc """
  Flush iptables and reinitialize firewall rules.
  """
  def reset() do
    flush_tables()

    # Make sure the devices can forward data between the different interfaces
    System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"])

    gateway_access()
    internet_forwarding()
    vpn_forwarding()
    internet_passthrough()
    dns_forwarding()
  end

  def get_env(:gateway), do: Application.get_env(:tunneld, :network)[:gateway]
  def get_env(:wlan), do: Application.get_env(:tunneld, :network)[:wlan]
  def get_env(:eth), do: Application.get_env(:tunneld, :network)[:eth]
  def get_env(:mullvad), do: Application.get_env(:tunneld, :network)[:mullvad]

  @doc """
  Flush all iptables rules.
  """
  def flush_tables() do
    System.cmd("iptables", ["-F"])
    System.cmd("iptables", ["-t", "nat", "-F"])
    System.cmd("iptables", ["-t", "mangle", "-F"])
  end

  defp gateway_access() do
    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      get_env(:eth),
      "-d",
      get_env(:gateway),
      "-j",
      "ACCEPT"
    ])

    for proto <- ["udp", "tcp"] do
      System.cmd("iptables", [
        "-A",
        "INPUT",
        "-i",
        get_env(:eth),
        "-p",
        proto,
        "--dport",
        "5336",
        "-j",
        "ACCEPT"
      ])
    end
  end

  defp internet_forwarding() do
    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      get_env(:eth),
      "-o",
      get_env(:wlan),
      "-m",
      "state",
      "--state",
      "NEW,ESTABLISHED,RELATED",
      "-j",
      "ACCEPT"
    ])

    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      get_env(:wlan),
      "-o",
      get_env(:eth),
      "-m",
      "state",
      "--state",
      "ESTABLISHED,RELATED",
      "-j",
      "ACCEPT"
    ])
  end

  defp internet_passthrough() do
    System.cmd("iptables", [
      "-t",
      "nat",
      "-A",
      "POSTROUTING",
      "-o",
      get_env(:wlan),
      "-j",
      "MASQUERADE"
    ])

    System.cmd("iptables", [
      "-t",
      "nat",
      "-A",
      "POSTROUTING",
      "-o",
      get_env(:mullvad),
      "-j",
      "MASQUERADE"
    ])
  end

  defp dns_forwarding() do
    System.cmd("iptables", [
      "-t",
      "nat",
      "-A",
      "PREROUTING",
      "-p",
      "udp",
      "--dport",
      "53",
      "-j",
      "REDIRECT",
      "--to-port",
      "5336"
    ])

    System.cmd("iptables", [
      "-t",
      "nat",
      "-A",
      "PREROUTING",
      "-p",
      "tcp",
      "--dport",
      "53",
      "-j",
      "REDIRECT",
      "--to-port",
      "5336"
    ])

    for proto <- ["udp", "tcp"] do
      System.cmd("iptables", [
        "-t",
        "nat",
        "-A",
        "OUTPUT",
        "-d",
        "127.0.0.1",
        "-p",
        proto,
        "--dport",
        "53",
        "-j",
        "REDIRECT",
        "--to-port",
        "5336"
      ])

      System.cmd("iptables", [
        "-t",
        "nat",
        "-A",
        "OUTPUT",
        "-d",
        get_env(:gateway),
        "-p",
        proto,
        "--dport",
        "53",
        "-j",
        "REDIRECT",
        "--to-port",
        "5336"
      ])
    end
  end

  defp vpn_forwarding() do
    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      get_env(:eth),
      "-o",
      get_env(:mullvad),
      "-m",
      "state",
      "--state",
      "NEW,ESTABLISHED,RELATED",
      "-j",
      "ACCEPT"
    ])

    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      get_env(:mullvad),
      "-o",
      get_env(:eth),
      "-m",
      "state",
      "--state",
      "ESTABLISHED,RELATED",
      "-j",
      "ACCEPT"
    ])
  end
end

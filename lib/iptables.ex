defmodule Iptables do
  @moduledoc """
  Module that will contain helper functions to interact with the firewall rules.
  This ensures all devices are blocked by default except for access to Tunneld.
  """

  # NOTE: we need to make a config file later to get the env from that change with the system

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

  @doc """
  Flush all iptables rules.
  """
  def flush_tables() do
    System.cmd("iptables", ["-F"])
    System.cmd("iptables", ["-t", "nat", "-F"])
    System.cmd("iptables", ["-t", "mangle", "-F"])
    IO.puts("Iptables flushed.")
  end

  # Gateway for interfaces regardless of blocking or dropping by default
  defp gateway_access() do
    # Allow clients to access Tunneld UI (gateway)
    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      Application.get_env(:tunneld, [:network, :eth]),
      "-d",
      Application.get_env(:tunneld, [:network, :gateway]),
      "-j",
      "ACCEPT"
    ])

    # System.cmd("iptables", ["-A", "FORWARD", "-i", @wlan0_interface, "-d", Application.get_env(:tunneld, [:network, :gateway]), "-j", "ACCEPT"])
  end

  # Make sure client interfaces can send/recieve packets from the internet interface
  defp internet_forwarding() do
    # interface > internet
    # System.cmd("iptables", ["-A", "FORWARD", "-i", @wlan0_interface, "-o", Application.get_env(:tunneld, [:network, :wlan]), "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      Application.get_env(:tunneld, [:network, :eth]),
      "-o",
      Application.get_env(:tunneld, [:network, :wlan]),
      "-m",
      "state",
      "--state",
      "RELATED,ESTABLISHED",
      "-j",
      "ACCEPT"
    ])

    # internet > interface
    # System.cmd("iptables", ["-A", "FORWARD", "-i", Application.get_env(:tunneld, [:network, :wlan]), "-o", @wlan0_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      Application.get_env(:tunneld, [:network, :wlan]),
      "-o",
      Application.get_env(:tunneld, [:network, :eth]),
      "-m",
      "state",
      "--state",
      "RELATED,ESTABLISHED",
      "-j",
      "ACCEPT"
    ])
  end

  # Allow internet packets through specific interfaces
  defp internet_passthrough() do
    # Enable NAT for whitelisted devices
    System.cmd("iptables", [
      "-t",
      "nat",
      "-A",
      "POSTROUTING",
      "-o",
      Application.get_env(:tunneld, [:network, :wlan]),
      "-j",
      "MASQUERADE"
    ])

    System.cmd("iptables", [
      "-t",
      "nat",
      "-A",
      "POSTROUTING",
      "-o",
      Application.get_env(:tunneld, [:network, :mullvad]),
      "-j",
      "MASQUERADE"
    ])
  end

  # DNS forwarding to a custom running service on a specific port (dnsmasq)
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
  end

  # VPN forwarding - Note this may change if the vpn server is running on another machine
  defp vpn_forwarding() do
    # Allow outgoing Wi-Fi -> VPN connections (this will need to be removed for a sentry later)
    # System.cmd("iptables", ["-A", "FORWARD", "-i", @wlan0_interface, "-o", Application.get_env(:tunneld, [:network, :mullvad]), "-j", "ACCEPT"])
    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      Application.get_env(:tunneld, [:network, :eth]),
      "-o",
      Application.get_env(:tunneld, [:network, :mullvad]),
      "-j",
      "ACCEPT"
    ])

    # Allow bidirectional forwarding between Wi-Fi and VPN (this will need to be removed for a sentry later)
    # System.cmd("iptables", ["-A", "FORWARD", "-i", Application.get_env(:tunneld, [:network, :mullvad]), "-o", @wlan0_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", [
      "-A",
      "FORWARD",
      "-i",
      Application.get_env(:tunneld, [:network, :mullvad]),
      "-o",
      Application.get_env(:tunneld, [:network, :eth]),
      "-m",
      "state",
      "--state",
      "RELATED,ESTABLISHED",
      "-j",
      "ACCEPT"
    ])
  end
end

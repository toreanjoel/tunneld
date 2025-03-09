defmodule Iptables do
  @moduledoc """
  Module that will contain helper functions to interact with the firewall rules.
  This ensures all devices are blocked by default except for access to Sentinel.
  """

  @internet_interface "wlan1"
  @vpn_interface "wg0-mullvad"
  @eth0_interface "br0"
  @wlan0_interface "wlan0"
  @gateway "10.0.0.1"

  @doc """
  Flush iptables and reinitialize firewall rules.
  """
  def reset() do
    flush_tables()

    # Make sure the devices can forward data between the different interfaces
    System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"])

    drop_all_connections()
    gateway_access()
    internet_forwarding()
    vpn_forwarding()
    internet_passthrough()
    dns_forwarding()

    IO.puts("Iptables reset: All traffic blocked by default. Only Sentinel UI is accessible.")
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

  @doc """
  Add user MAC entry to block internet access.
  """
  def add_user_entry(ip, mac) do
    System.cmd("iptables", [
      "-t", "mangle", "-I", "PREROUTING", "-m", "mac", "--mac-source", mac, "-d", ip, "-j", "DROP"
    ])
  end

  def remove_user_entry(ip, mac) do
    System.cmd("iptables", [
      "-t", "mangle", "-D", "PREROUTING", "-m", "mac", "--mac-source", mac, "-d", ip, "-j", "DROP"
    ])
  end

  @doc """
  Add system-wide blocking rule.
  """
  def add_system_entry(ip) do
    System.cmd("iptables", [
      "-t", "mangle", "-I", "PREROUTING", "-d", ip, "-j", "DROP"
    ])
  end

  def remove_system_entry(ip) do
    System.cmd("iptables", [
      "-t", "mangle", "-D", "PREROUTING", "-d", ip, "-j", "DROP"
    ])
  end

  @spec has_user_entry?(binary(), binary()) :: {any(), non_neg_integer()}
  @doc """
  Check if a user is already blocked.
  """
  def has_user_entry?(ip, mac) do
    System.cmd("iptables", [
      "-t", "mangle", "-C", "PREROUTING", "-m", "mac", "--mac-source", mac, "-d", ip, "-j", "DROP"
    ])
  end

  @doc """
  Check if a system-wide block exists.
  """
  def has_system_entry?(ip) do
    System.cmd("iptables", [
      "-t", "mangle", "-C", "PREROUTING", "-d", ip, "-j", "DROP"
    ])
  end

  @doc """
  Grant a device (by MAC and IP) internet access by allowing FORWARD and POSTROUTING.
  """
  def grant_access(ip, mac) do
    # Ensure the device can forward traffic through the internet interface
    System.cmd("iptables", ["-I", "FORWARD", "1", "-s", ip, "-m", "mac", "--mac-source", mac, "-o", @internet_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-I", "FORWARD", "1", "-s", ip, "-m", "mac", "--mac-source", mac, "-o", @vpn_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-I", "FORWARD", "1", "-i", @internet_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])

    # Ensure the device is allowed through NAT
    System.cmd("iptables", ["-I", "POSTROUTING", "1", "-t", "nat", "-s", ip, "-j", "MASQUERADE"])

    IO.puts("Granted internet access to #{ip} (MAC: #{mac})")
  end

  @doc """
  Revoke a device's internet access (block MAC and IP).
  """
  def revoke_access(ip, mac) do
    System.cmd("iptables", ["-D", "FORWARD", "-s", ip, "-m", "mac", "--mac-source", mac, "-o", @internet_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-D", "FORWARD", "-s", ip, "-m", "mac", "--mac-source", mac, "-o", @vpn_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-D", "FORWARD", "-i", @internet_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", ["-D", "POSTROUTING", "-t", "nat", "-s", ip, "-j", "MASQUERADE"])

    IO.puts("Revoked internet access for #{ip} (MAC: #{mac})")
  end

  @doc """
  Drop connections from the main interfaces initially
  """
  defp drop_all_connections() do
    # Block all forwarding by default
    System.cmd("iptables", ["-P", "FORWARD", "DROP"])
    # Block non-whitelisted users from VPN access
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wlan0_interface, "-o", @vpn_interface, "-j", "DROP"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @eth0_interface, "-o", @vpn_interface, "-j", "DROP"])
  end

  @doc """
  Gateway for interfaces regardless of blocking or dropping by default
  """
  defp gateway_access() do
    # Allow clients to access Sentinel UI (gateway)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @eth0_interface, "-d", @gateway, "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wlan0_interface, "-d", @gateway, "-j", "ACCEPT"])
  end

  @doc """
  Make sure client interfaces can send/recieve packets from the internet interface
  """
  defp internet_forwarding() do
    # interface > internet
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wlan0_interface, "-o", @internet_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @eth0_interface, "-o", @internet_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])

    # internet > interface
    System.cmd("iptables", ["-A", "FORWARD", "-i", @internet_interface, "-o", @wlan0_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @internet_interface, "-o", @eth0_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
  end

  @doc """
  Allow internet packets through specific interfaces
  """
  defp internet_passthrough() do
    # Enable NAT for whitelisted devices
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @internet_interface, "-j", "MASQUERADE"])
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @vpn_interface, "-j", "MASQUERADE"])
  end

  @doc """
  DNS forwarding to a custom running service on a specific port (dnsmasq)
  """
  defp dns_forwarding() do
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "udp", "--dport", "53", "-j", "REDIRECT", "--to-port", "5336"])
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "53", "-j", "REDIRECT", "--to-port", "5336"])
  end

  @doc """
  VPN forwarding - Note this may change if the vpn server is running on another machine
  """
  defp vpn_forwarding() do
    # Allow outgoing Wi-Fi -> VPN connections (this will need to be removed for a sentry later)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wlan0_interface, "-o", @vpn_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @eth0_interface, "-o", @vpn_interface, "-j", "ACCEPT"])

    # Allow bidirectional forwarding between Wi-Fi and VPN (this will need to be removed for a sentry later)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @vpn_interface, "-o", @wlan0_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @vpn_interface, "-o", @eth0_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
  end
end

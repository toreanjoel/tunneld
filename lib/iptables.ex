defmodule Iptables do
  @moduledoc """
  Module that will contain helper functions to interact with the firewall rules.
  This ensures all devices are blocked by default except for access to Sentinel.
  """

  @internet_interface "eth0"   # Update if different
  @vpn_interface "wg0-mullvad" # VPN interface (if used)
  @wifi_interface "wlan1"      # Wireless interface
  @sentinel_ip "10.0.0.1"   # Sentinel Gateway - This can be a config

  @doc """
  Flush iptables and reinitialize firewall rules.
  """
  def reset() do
    flush_tables()

    System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"])

    # Block all forwarding by default
    System.cmd("iptables", ["-P", "FORWARD", "DROP"])

    # Allow Wi-Fi clients to access Sentinel UI (gateway)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-d", @sentinel_ip, "-j", "ACCEPT"])

    # Allow bidirectional forwarding between Wi-Fi and Internet (only for approved devices)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-o", @internet_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @internet_interface, "-o", @wifi_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])

    # Allow outgoing Wi-Fi -> VPN connections (NEW RULE)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-o", @vpn_interface, "-j", "ACCEPT"])

    # Allow bidirectional forwarding between Wi-Fi and VPN
    System.cmd("iptables", ["-A", "FORWARD", "-i", @vpn_interface, "-o", @wifi_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])

    # Enable NAT for whitelisted devices
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @internet_interface, "-j", "MASQUERADE"])
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @vpn_interface, "-j", "MASQUERADE"])

    # Redirect all DNS queries to dnsmasq (port 5336)
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "udp", "--dport", "53", "-j", "REDIRECT", "--to-port", "5336"])
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "53", "-j", "REDIRECT", "--to-port", "5336"])


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
    System.cmd("iptables", ["-A", "FORWARD", "-s", ip, "-m", "mac", "--mac-source", mac, "-o", @internet_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @internet_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])

    # Ensure the device is allowed through NAT
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-s", ip, "-j", "MASQUERADE"])

    IO.puts("Granted internet access to #{ip} (MAC: #{mac})")
  end

  @doc """
  Revoke a device's internet access (block MAC and IP).
  """
  def revoke_access(ip, mac) do
    System.cmd("iptables", ["-D", "FORWARD", "-s", ip, "-m", "mac", "--mac-source", mac, "-o", @internet_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-D", "FORWARD", "-i", @internet_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])
    System.cmd("iptables", ["-t", "nat", "-D", "POSTROUTING", "-s", ip, "-j", "MASQUERADE"])

    IO.puts("Revoked internet access for #{ip} (MAC: #{mac})")
  end
end

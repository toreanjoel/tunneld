defmodule Iptables do
  @moduledoc """
  Module that will contain helper functions to interact with the firewall rules.
  This ensures all devices are blocked by default except for access to Sentinel.
  """

  @internet_interface "eth0"   # Update if different
  @vpn_interface "wg0-mullvad" # VPN interface (if used)
  @wifi_interface "wlan0"      # Wireless interface
  @sentinel_ip "10.0.0.1"   # Sentinel Gateway - This can be a config

  @doc """
  Flush iptables and reinitialize firewall rules with no internet access by default.
  """
  def reset() do
    flush()  # Clear all iptables rules first

    # Enable IP forwarding
    System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"])

    # Block all forwarding by default (no internet access for any device)
    System.cmd("iptables", ["-P", "FORWARD", "DROP"])

    # Allow Wi-Fi clients to access Sentinel UI (gateway at @sentinel_ip)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-d", @sentinel_ip, "-j", "ACCEPT"])

    # Allow Wi-Fi clients to communicate within the local network (optional)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-o", @wifi_interface, "-j", "ACCEPT"])

    # Allow NAT for internet access (ONLY for whitelisted devices)
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @internet_interface, "-j", "MASQUERADE"])
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @vpn_interface, "-j", "MASQUERADE"])

    # Redirect DNS requests to dnsmasq (ensures captive portal works)
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "udp", "--dport", "53", "-j", "REDIRECT", "--to-port", "5336"])
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "53", "-j", "REDIRECT", "--to-port", "5336"])

    # Captive Portal Rules (Forcing All HTTP Requests to Sentinel)
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "80", "-j", "DNAT", "--to-destination", @sentinel_ip])

    # Block HTTPS so devices detect the captive portal (forces pop-up)
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "443", "-j", "REJECT"])

    IO.puts("Iptables reset: Internet blocked for all devices by default. Only Sentinel UI is accessible.")
  end

  @doc """
  Flush all iptables rules.
  """
  def flush() do
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
end

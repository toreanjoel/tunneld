defmodule Iptables do
  @moduledoc """
  Module that will contain helper functions to interact with the firewall rules
  """

  @internet_interface "eth0"   # Update if different
  @vpn_interface "wg0-mullvad" # VPN interface (if used)
  @wifi_interface "wlan0"      # Wireless interface

  @doc """
  Flush iptables and reinitialize firewall rules
  """
  def reset() do
    flush()  # Clear all iptables rules first

    # Enable IP forwarding
    System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"])

    # Setup NAT for outgoing traffic
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @internet_interface, "-j", "MASQUERADE"])
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @vpn_interface, "-j", "MASQUERADE"])

    # Allow forwarded traffic between interfaces
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-o", @internet_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @internet_interface, "-o", @wifi_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])

    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-o", @vpn_interface, "-j", "ACCEPT"])
    System.cmd("iptables", ["-A", "FORWARD", "-i", @vpn_interface, "-o", @wifi_interface, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"])

    # Port forward DNS requests to dnsmasq
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "udp", "--dport", "53", "-j", "REDIRECT", "--to-port", "5336"])
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "53", "-j", "REDIRECT", "--to-port", "5336"])

    IO.puts("Iptables reset and firewall rules initialized.")
  end

  @doc """
  Flush all iptables rules
  """
  def flush() do
    System.cmd("iptables", ["-F"])
    System.cmd("iptables", ["-t", "nat", "-F"])
    System.cmd("iptables", ["-t", "mangle", "-F"])
    IO.puts("Iptables flushed.")
  end

  @doc """
  Add user MAC entry to block internet access
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
  Add system-wide blocking rule
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
  Check if a user is already blocked
  """
  def has_user_entry?(ip, mac) do
    System.cmd("iptables", [
      "-t", "mangle", "-C", "PREROUTING", "-m", "mac", "--mac-source", mac, "-d", ip, "-j", "DROP"
    ])
  end

  @doc """
  Check if a system-wide block exists
  """
  def has_system_entry?(ip) do
    System.cmd("iptables", [
      "-t", "mangle", "-C", "PREROUTING", "-d", ip, "-j", "DROP"
    ])
  end
end

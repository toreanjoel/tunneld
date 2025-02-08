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
  Flush iptables and reinitialize firewall rules.
  """
  def reset() do
    flush()  # Clear existing firewall rules

    gateway_ip = get_gateway_ip()
    IO.puts("Detected Gateway IP: #{gateway_ip}")

    # Enable IP forwarding
    System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"])

    # Block all forwarding by default
    System.cmd("iptables", ["-P", "FORWARD", "DROP"])

    # Allow Wi-Fi clients to access Sentinel UI
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-d", gateway_ip, "-j", "ACCEPT"])

    # Allow Wi-Fi clients to communicate with each other (optional)
    System.cmd("iptables", ["-A", "FORWARD", "-i", @wifi_interface, "-o", @wifi_interface, "-j", "ACCEPT"])

    # Enable NAT for whitelisted devices
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @internet_interface, "-j", "MASQUERADE"])
    System.cmd("iptables", ["-t", "nat", "-A", "POSTROUTING", "-o", @vpn_interface, "-j", "MASQUERADE"])

    # Captive portal redirection (HTTP traffic to Sentinel)
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "80", "-j", "DNAT", "--to-destination", @sentinel_ip])

    # Block HTTPS to force captive portal pop-up
    System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "443", "-j", "REJECT"])

    # Redirect captive portal detection URLs
    captive_urls = [
      "connectivitycheck.gstatic.com",
      "captive.apple.com",
      "msftconnecttest.com",
      "hotspot-detect.html"
    ]

    Enum.each(captive_urls, fn url ->
      System.cmd("iptables", ["-t", "nat", "-A", "PREROUTING", "-p", "tcp", "--dport", "80", "-m", "string", "--string", url, "--algo", "bm", "-j", "DNAT", "--to-destination", gateway_ip])
    end)

    IO.puts("Iptables reset: Captive Portal Enabled. Internet blocked by default. Only Sentinel UI is accessible.")
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

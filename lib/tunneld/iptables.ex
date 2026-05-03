defmodule Tunneld.Iptables do
  @moduledoc """
  Configures iptables firewall rules for the Tunneld gateway.

  On startup (production only), flushes all existing rules and sets up:
  - IP forwarding between ethernet and WiFi interfaces
  - NAT masquerading for internet access via WiFi and VPN
  - DNS redirection: all port-53 traffic is redirected to port 5336
    (where dnsmasq listens) for consistent subnet DNS resolution
  - Gateway access rules allowing devices to reach the Tunneld host
  - Mesh WireGuard interface forwarding when mesh is enabled

  This module is called once at application start and is not a GenServer.
  """

  @doc """
  Flush iptables and reinitialize firewall rules.
  """
  def reset() do
    flush_tables()

    # Set default DROP policies immediately after flush to minimize
    # the window where no firewall rules are active
    System.cmd("iptables", ["-P", "INPUT", "DROP"])
    System.cmd("iptables", ["-P", "FORWARD", "DROP"])
    System.cmd("iptables", ["-P", "OUTPUT", "ACCEPT"])

    # Allow loopback
    System.cmd("iptables", ["-A", "INPUT", "-i", "lo", "-j", "ACCEPT"])

    # Allow return traffic for outgoing connections
    System.cmd("iptables", [
      "-A",
      "INPUT",
      "-m",
      "conntrack",
      "--ctstate",
      "ESTABLISHED,RELATED",
      "-j",
      "ACCEPT"
    ])

    # Allow gateway services (HTTP dashboard, SSH)
    for port <- [80, 22] do
      System.cmd("iptables", [
        "-A",
        "INPUT",
        "-p",
        "tcp",
        "--dport",
        to_string(port),
        "-j",
        "ACCEPT"
      ])
    end

    # Allow DHCP requests from LAN clients
    System.cmd("iptables", [
      "-A",
      "INPUT",
      "-i",
      get_env(:eth),
      "-p",
      "udp",
      "--dport",
      "67",
      "-j",
      "ACCEPT"
    ])

    # Make sure the devices can forward data between the different interfaces
    System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"])

    gateway_access()
    internet_forwarding()
    vpn_forwarding()
    internet_passthrough()
    dns_forwarding()
    set_dns_server(Tunneld.Servers.DnsConfig.get_dns_server())
  end

  def get_env(:gateway), do: Application.get_env(:tunneld, :network)[:gateway]
  def get_env(:wlan), do: Application.get_env(:tunneld, :network)[:wlan]
  def get_env(:eth), do: Application.get_env(:tunneld, :network)[:eth]
  def get_env(:vpn), do: Application.get_env(:tunneld, :network)[:mullvad]

  @doc """
  Flush all iptables rules.
  """
  def flush_tables() do
    System.cmd("iptables", ["-F"])
    System.cmd("iptables", ["-t", "nat", "-F"])
    System.cmd("iptables", ["-t", "mangle", "-F"])
  end

  defp append_unique(cmd, args) do
    # Replace -A with -C to check if the rule already exists
    check_args =
      Enum.map(args, fn
        "-A" -> "-C"
        other -> other
      end)

    case System.cmd(cmd, check_args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> System.cmd(cmd, args, stderr_to_stdout: true)
    end

    :ok
  end

  defp del(cmd, args) do
    # Fire-and-forget: rule may not exist, that's fine
    System.cmd(cmd, args, stderr_to_stdout: true)
    :ok
  end

  def set_dns_server(dns_server) do
    # Remove existing exemptions
    for proto <- ["udp", "tcp"] do
      del("iptables", [
        "-t",
        "nat",
        "-D",
        "OUTPUT",
        "-d",
        dns_server,
        "-p",
        proto,
        "--dport",
        "53",
        "-j",
        "ACCEPT",
        "-m",
        "comment",
        "--comment",
        "tunneld-dns-exempt"
      ])

      del("iptables", [
        "-t",
        "nat",
        "-D",
        "PREROUTING",
        "-s",
        dns_server,
        "-p",
        proto,
        "--dport",
        "53",
        "-j",
        "RETURN",
        "-m",
        "comment",
        "--comment",
        "tunneld-dns-exempt"
      ])
    end

    # Add new exemptions — INSERT before the REDIRECT rules
    for proto <- ["udp", "tcp"] do
      System.cmd("iptables", [
        "-t",
        "nat",
        "-I",
        "PREROUTING",
        "1",
        "-s",
        dns_server,
        "-p",
        proto,
        "--dport",
        "53",
        "-j",
        "RETURN",
        "-m",
        "comment",
        "--comment",
        "tunneld-dns-exempt"
      ])

      append_unique("iptables", [
        "-t",
        "nat",
        "-A",
        "OUTPUT",
        "-d",
        dns_server,
        "-p",
        proto,
        "--dport",
        "53",
        "-j",
        "ACCEPT",
        "-m",
        "comment",
        "--comment",
        "tunneld-dns-exempt"
      ])
    end
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

    vpn_iface = get_env(:vpn)

    if vpn_iface != nil and vpn_iface != "" do
      System.cmd("iptables", [
        "-t",
        "nat",
        "-A",
        "POSTROUTING",
        "-o",
        vpn_iface,
        "-j",
        "MASQUERADE"
      ])
    end
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
    vpn = get_env(:vpn)

    if vpn && vpn != "" do
      System.cmd("iptables", [
        "-A",
        "FORWARD",
        "-i",
        get_env(:eth),
        "-o",
        vpn,
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
        vpn,
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

end

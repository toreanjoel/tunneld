defmodule Tunneld.Iptables do
  @moduledoc """
  Configures iptables firewall rules for the Tunneld gateway.

  On startup (production only), flushes all existing rules and sets up:
  - IP forwarding between ethernet and WiFi interfaces
  - NAT masquerading for internet access via WiFi and VPN
  - DNS redirection: all port-53 traffic is redirected to port 5336
    (where dnscrypt-proxy listens) to enforce encrypted DNS
  - Gateway access rules allowing devices to reach the Tunneld host
  - WireGuard VPN forwarding and masquerading (applied dynamically)

  This module is called once at application start and is not a GenServer.
  """

  @wg_interface "wg0"

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
    System.cmd("iptables", ["-A", "INPUT", "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT"])

    # Make sure the devices can forward data between the different interfaces
    System.cmd("sysctl", ["-w", "net.ipv4.ip_forward=1"])

    gateway_access()
    internet_forwarding()
    vpn_forwarding()
    internet_passthrough()
    dns_forwarding()

    # Re-apply WireGuard rules if the VPN server is enabled
    if wireguard_enabled?(), do: wireguard_up()
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

  # --- WireGuard Rules ---

  @doc """
  Apply iptables rules for the WireGuard VPN server.

  Sets up:
  - FORWARD: wg0 -> eth (established, related) — allows VPN peers to reach Ethernet subnet
  - FORWARD: eth -> wg0 (established, related) — allows return traffic to VPN peers
  - FORWARD: wg0 -> wlan (new, established, related) — allows VPN peers to reach internet
  - NAT MASQUERADE: wg0 subnet -> wlan — full-tunnel peers exit through upstream
  - INPUT: accept UDP on WireGuard listen port

  Must be called when the VPN server is enabled. Idempotent — each rule
  is checked before being appended, preventing duplicates on re-apply.
  """
  def wireguard_up do
    eth = get_env(:eth)
    wlan = get_env(:wlan)
    port = wireguard_listen_port()

    # FORWARD: allow VPN peers to reach Ethernet subnet
    append_unique("iptables", [
      "-A", "FORWARD",
      "-i", @wg_interface,
      "-o", eth,
      "-m", "conntrack",
      "--ctstate", "ESTABLISHED,RELATED",
      "-j", "ACCEPT",
      "-m", "comment", "--comment", "tunneld-wg-forward-eth"
    ])

    # FORWARD: allow return traffic from Ethernet to VPN peers
    append_unique("iptables", [
      "-A", "FORWARD",
      "-i", eth,
      "-o", @wg_interface,
      "-m", "conntrack",
      "--ctstate", "ESTABLISHED,RELATED",
      "-j", "ACCEPT",
      "-m", "comment", "--comment", "tunneld-wg-return-eth"
    ])

    # FORWARD: allow VPN peers to initiate to Ethernet subnet
    append_unique("iptables", [
      "-A", "FORWARD",
      "-i", @wg_interface,
      "-o", eth,
      "-m", "conntrack",
      "--ctstate", "NEW,ESTABLISHED,RELATED",
      "-j", "ACCEPT",
      "-m", "comment", "--comment", "tunneld-wg-init-eth"
    ])

    # FORWARD: allow VPN peers to reach internet via WiFi upstream
    append_unique("iptables", [
      "-A", "FORWARD",
      "-i", @wg_interface,
      "-o", wlan,
      "-m", "conntrack",
      "--ctstate", "NEW,ESTABLISHED,RELATED",
      "-j", "ACCEPT",
      "-m", "comment", "--comment", "tunneld-wg-forward-wlan"
    ])

    # FORWARD: allow return traffic from WiFi to VPN peers
    append_unique("iptables", [
      "-A", "FORWARD",
      "-i", wlan,
      "-o", @wg_interface,
      "-m", "conntrack",
      "--ctstate", "ESTABLISHED,RELATED",
      "-j", "ACCEPT",
      "-m", "comment", "--comment", "tunneld-wg-return-wlan"
    ])

    # NAT MASQUERADE: full-tunnel peers exit through upstream
    append_unique("iptables", [
      "-t", "nat",
      "-A", "POSTROUTING",
      "-o", wlan,
      "-j", "MASQUERADE",
      "-m", "comment", "--comment", "tunneld-wg-masq"
    ])

    # INPUT: accept UDP on WireGuard listen port
    append_unique("iptables", [
      "-A", "INPUT",
      "-p", "udp",
      "--dport", to_string(port),
      "-j", "ACCEPT",
      "-m", "comment", "--comment", "tunneld-wg-input"
    ])

    :ok
  end

  @doc """
  Remove iptables rules for the WireGuard VPN server.

  Deletes each rule by matching the same specification used in `wireguard_up/0`.
  Safe to call even if rules don't exist — errors are ignored.
  """
  def wireguard_down do
    eth = get_env(:eth)
    wlan = get_env(:wlan)
    port = wireguard_listen_port()

    # Delete FORWARD rules
    del("iptables", ["-D", "FORWARD", "-i", @wg_interface, "-o", eth, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT", "-m", "comment", "--comment", "tunneld-wg-forward-eth"])
    del("iptables", ["-D", "FORWARD", "-i", eth, "-o", @wg_interface, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT", "-m", "comment", "--comment", "tunneld-wg-return-eth"])
    del("iptables", ["-D", "FORWARD", "-i", @wg_interface, "-o", eth, "-m", "conntrack", "--ctstate", "NEW,ESTABLISHED,RELATED", "-j", "ACCEPT", "-m", "comment", "--comment", "tunneld-wg-init-eth"])
    del("iptables", ["-D", "FORWARD", "-i", @wg_interface, "-o", wlan, "-m", "conntrack", "--ctstate", "NEW,ESTABLISHED,RELATED", "-j", "ACCEPT", "-m", "comment", "--comment", "tunneld-wg-forward-wlan"])
    del("iptables", ["-D", "FORWARD", "-i", wlan, "-o", @wg_interface, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT", "-m", "comment", "--comment", "tunneld-wg-return-wlan"])

    # Delete NAT masquerade
    del("iptables", ["-t", "nat", "-D", "POSTROUTING", "-o", wlan, "-j", "MASQUERADE", "-m", "comment", "--comment", "tunneld-wg-masq"])

    # Delete INPUT rule
    del("iptables", ["-D", "INPUT", "-p", "udp", "--dport", to_string(port), "-j", "ACCEPT", "-m", "comment", "--comment", "tunneld-wg-input"])

    :ok
  end

  defp append_unique(cmd, args) do
    # Replace -A with -C to check if the rule already exists
    check_args = Enum.map(args, fn
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
      get_env(:vpn),
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
      get_env(:vpn),
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
      get_env(:vpn),
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

  # --- WireGuard Helpers ---

  defp wireguard_enabled? do
    if _pid = GenServer.whereis(Tunneld.Servers.Wireguard) do
      Tunneld.Servers.Wireguard.get_state()["enabled"] == true
    else
      false
    end
  end

  defp wireguard_listen_port do
    if _pid = GenServer.whereis(Tunneld.Servers.Wireguard) do
      Tunneld.Servers.Wireguard.get_state()["listen_port"] || 51820
    else
      51820
    end
  end
end

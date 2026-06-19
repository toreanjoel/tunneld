defmodule Tunneld.Iptables do
  @moduledoc """
  Configures iptables firewall rules for the Tunneld gateway.

  On startup (production only), flushes all existing rules and sets up:
  - IP forwarding between the downstream (LAN) and upstream (internet) interfaces
  - NAT masquerading for internet access via the upstream interface
  - DNS redirection: all port-53 traffic is redirected to port 5336
    (where dnsmasq listens) for consistent subnet DNS resolution
  - Gateway access rules allowing devices to reach the Tunneld host
  - Mesh WireGuard interface forwarding when mesh is enabled

  Interface names are read from app config (`:tunneld, :network` -> `:upstream`,
  `:downstream`) and are never hardcoded in this module.

  This module is called once at application start and is not a GenServer.
  """

  @doc """
  Flush iptables and reinitialize firewall rules.
  """
  def reset() do
    flush_tables()

    # IMPORTANT: keep default ACCEPT policies until rules are in place,
    # otherwise an existing SSH session over which we deploy can be
    # dropped between -F and the subsequent -A rules.
    System.cmd("iptables", ["-P", "INPUT", "ACCEPT"])
    System.cmd("iptables", ["-P", "FORWARD", "ACCEPT"])
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
      get_env(:downstream),
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
    internet_passthrough()
    dns_forwarding()
    set_dns_server(Tunneld.Servers.DnsConfig.get_dns_server())

    # Set DROP policies LAST, after all rules are in place,
    # so existing SSH sessions survive the transition.
    System.cmd("iptables", ["-P", "INPUT", "DROP"])
    System.cmd("iptables", ["-P", "FORWARD", "DROP"])
  end

  def get_env(:gateway), do: Application.get_env(:tunneld, :network)[:gateway]
  def get_env(:upstream), do: Application.get_env(:tunneld, :network)[:upstream]
  def get_env(:downstream), do: Application.get_env(:tunneld, :network)[:downstream]

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

    # Add new exemptions - INSERT before the REDIRECT rules
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
      get_env(:downstream),
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
        get_env(:downstream),
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
      get_env(:downstream),
      "-o",
      get_env(:upstream),
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
      get_env(:upstream),
      "-o",
      get_env(:downstream),
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
      get_env(:upstream),
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

  def add_mesh_forwarding do
    iface = "wg-mesh"
    downstream = get_env(:downstream)

    if downstream == nil or downstream == "" do
      :noop
    else
      case System.cmd("ip", ["link", "show", iface], stderr_to_stdout: true) do
        {_, 0} ->
          append_unique("iptables", [
            "-A",
            "FORWARD",
            "-i",
            iface,
            "-o",
            downstream,
            "-m",
            "state",
            "--state",
            "NEW,ESTABLISHED,RELATED",
            "-j",
            "ACCEPT"
          ])

          append_unique("iptables", [
            "-A",
            "FORWARD",
            "-i",
            downstream,
            "-o",
            iface,
            "-m",
            "state",
            "--state",
            "NEW,ESTABLISHED,RELATED",
            "-j",
            "ACCEPT"
          ])

          append_unique("iptables", [
            "-t",
            "nat",
            "-A",
            "POSTROUTING",
            "-o",
            iface,
            "-j",
            "MASQUERADE"
          ])

          append_unique("iptables", [
            "-A",
            "INPUT",
            "-i",
            iface,
            "-m",
            "state",
            "--state",
            "ESTABLISHED,RELATED",
            "-j",
            "ACCEPT"
          ])

          append_unique("iptables", [
            "-A",
            "INPUT",
            "-i",
            iface,
            "-j",
            "ACCEPT"
          ])

          :ok

        _ ->
          :noop
      end
    end
  end

  def remove_mesh_forwarding do
    iface = "wg-mesh"
    downstream = get_env(:downstream)

    if downstream != nil and downstream != "" do
      for {in_if, out_if, states} <- [
            {iface, downstream, "NEW,ESTABLISHED,RELATED"},
            {downstream, iface, "NEW,ESTABLISHED,RELATED"}
          ] do
        del("iptables", [
          "-D",
          "FORWARD",
          "-i",
          in_if,
          "-o",
          out_if,
          "-m",
          "state",
          "--state",
          states,
          "-j",
          "ACCEPT"
        ])
      end

      del("iptables", [
        "-t",
        "nat",
        "-D",
        "POSTROUTING",
        "-o",
        iface,
        "-j",
        "MASQUERADE"
      ])

      del("iptables", [
        "-D",
        "INPUT",
        "-i",
        iface,
        "-m",
        "state",
        "--state",
        "ESTABLISHED,RELATED",
        "-j",
        "ACCEPT"
      ])

      del("iptables", [
        "-D",
        "INPUT",
        "-i",
        iface,
        "-j",
        "ACCEPT"
      ])
    end

    :ok
  end
end
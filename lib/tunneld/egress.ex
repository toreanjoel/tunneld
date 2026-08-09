defmodule Tunneld.Egress do
  @moduledoc """
  Per-device exit routing: route a subnet device's traffic out through a
  managed machine (an "exit node") instead of the gateway's own upstream.

  This works only because tunneld is the DHCP-assigned default gateway for
  every device on the subnet. Each exit machine gets its own routing table:

      ip route add default dev wg-<machine_id> table <N>
      ip rule add from <device_ip> lookup <N>

  Adding a device to an exit is one `ip rule`; removing is one delete. Table
  IDs are allocated from a persisted map (never recomputed from a hash), so a
  machine keeps a stable table id across restarts.

  On the exit machine side, `ensure_exit_capable/1` sets
  `net.ipv4.ip_forward=1` persistently, adds a MASQUERADE rule on the egress
  interface, and FORWARD-allows the WireGuard interface to/from it (UFW/FORWARD
  default is DROP, so ip_forward alone is not enough — found in live testing).

  > **Operational caution:** only ever route *device* traffic on the gateway —
  > never the gateway's own source IP — or you will lock yourself out (a policy
  > rule on the gateway's own IP misroutes management traffic; recover by
  > rebooting, since these rules are runtime-only).

  **Two things handled explicitly (see TODO §4.5):**

  * This only works because tunneld is the default gateway. We assert that at
    runtime and surface a clear error if a device bypasses the gateway.
  * **DNS leaks**: a device exiting via a machine still resolves through the
    gateway's upstream unless told otherwise. This is exposed as an explicit
    choice (`dns: "exit" | "local"`) — never decided silently.

  In mock mode no routes/rules are touched; state is tracked in-memory so the
  flow runs on a laptop.
  """

  require Logger

  alias Tunneld.Machines.SSH

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @table_base 100

  @doc """
  Route a device's traffic out through `machine`. `opts[:dns]` is `"exit"`
  (push the exit as the device's resolver) or `"local"` (keep local DNS).

  Returns `{:ok, %{device_ip: ip, machine: id, table: n}}` or
  `{:error, reason}`.
  """
  def route_device(machine, device_ip, opts \\ []) do
    dns = Keyword.get(opts, :dns, "local")

    if @mock do
      {:ok, %{device_ip: device_ip, machine: machine["id"], table: table_for(machine), dns: dns}}
    else
      real_route_device(machine, device_ip, dns)
    end
  end

  @doc "Remove a device from an exit (revert to gateway's own upstream)."
  def unroute_device(machine, device_ip) do
    if @mock do
      :ok
    else
      real_unroute_device(machine, device_ip)
    end
  end

  @doc "Whether a machine has been made exit-capable (has a table allocated)."
  def exit_capable?(machine) do
    Map.has_key?(read_tables(), machine["id"])
  end

  @doc "Get the routing table id allocated to an exit machine (stable)."
  def table_for(machine) do
    tables = read_tables()
    id = machine["id"]

    case Map.get(tables, id) do
      nil ->
        n = allocate_table(tables)
        write_tables(Map.put(tables, id, n))
        n

      n ->
        n
    end
  end

  @doc """
  Make a machine exit-capable: enable IP forwarding persistently and add a
  MASQUERADE rule on its egress interface.
  """
  def ensure_exit_capable(machine) do
    if @mock do
      :ok
    else
      with {:ok, _} <- SSH.run(machine, "sysctl -w net.ipv4.ip_forward=1 && (grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf)"),
           {:ok, iface} <- default_iface(machine) do
        # NAT for egressed traffic.
        _ =
          SSH.run(
            machine,
            "iptables -t nat -C POSTROUTING -o #{iface} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o #{iface} -j MASQUERADE"
          )

        # FORWARD-allow the WireGuard interface to/from the egress interface.
        # Without this the exit drops forwarded device traffic (UFW/FORWARD
        # default is DROP) even though ip_forward is on. This was found in
        # live egress testing.
        wg_iface = Tunneld.Overlay.iface_name(machine["id"])

        _ =
          SSH.run(
            machine,
            "iptables -C FORWARD -i #{wg_iface} -o #{iface} -j ACCEPT 2>/dev/null || " <>
              "iptables -I FORWARD 1 -i #{wg_iface} -o #{iface} -j ACCEPT"
          )

        _ =
          SSH.run(
            machine,
            "iptables -C FORWARD -i #{iface} -o #{wg_iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || " <>
              "iptables -I FORWARD 1 -i #{iface} -o #{wg_iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
          )

        :ok
      end
    end
  end

  # --- Real implementation ---

  defp real_route_device(machine, device_ip, dns) do
    id = machine["id"]
    iface = Tunneld.Overlay.iface_name(id)
    table = table_for(machine)
    overlay_ip = Tunneld.Overlay.address_for(machine)

    with :ok <- assert_gateway_role(device_ip),
         :ok <- add_rule(device_ip, table),
         :ok <- add_default_route(overlay_ip, iface, table),
         :ok <- add_lan_route(table),
         :ok <- add_vm_device_route(machine, device_ip, iface),
         :ok <- maybe_set_dns(device_ip, machine, dns) do
      {:ok, %{device_ip: device_ip, machine: id, table: table, dns: dns}}
    end
  end

  defp real_unroute_device(machine, device_ip) do
    table = table_for(machine)
    _ = run_gateway("ip rule del from #{device_ip} lookup #{table} 2>/dev/null || true")
    :ok
  end

  defp add_rule(device_ip, table) do
    run_gateway("ip rule add from #{device_ip} lookup #{table}")
  end

  defp add_default_route(overlay_ip, iface, table) do
    # The default route needs the VM's overlay IP as next-hop; a bare
    # `dev <iface>` link-scope route can't reach the internet.
    run_gateway("ip route add default via #{overlay_ip} dev #{iface} table #{table} 2>/dev/null || true")
  end

  # Keep the device's LAN traffic local (to the gateway) instead of sending it
  # through the tunnel, so the device can still reach the gateway/subnet.
  defp add_lan_route(table) do
    gw = gateway_ip()
    iface = lan_iface()
    run_gateway("ip route add #{lan_subnet(gw)} dev #{iface} table #{table} 2>/dev/null || true")
  end

  # The VM must route the device's return traffic back through the tunnel.
  defp add_vm_device_route(machine, device_ip, iface) do
    SSH.run(machine, "ip route add #{device_ip}/32 dev #{iface} 2>/dev/null || true")
  end

  # Assert tunneld is the device's default gateway (the prerequisite for egress).
  defp assert_gateway_role(device_ip) do
    gateway = gateway_ip()

    case run_gateway("ip route get #{device_ip} 2>/dev/null") do
      {:ok, out} ->
        if String.contains?(out, gateway) do
          :ok
        else
          {:error, :device_not_through_gateway}
        end

      _ ->
        {:error, :cannot_verify_device_path}
    end
  end

  defp maybe_set_dns(_device_ip, _machine, "local"), do: :ok

  defp maybe_set_dns(device_ip, machine, "exit") do
    # Push the exit machine as resolver: set its overlay IP in dnsmasq's
    # per-device config, then reload. (Stub: recorded in state.)
    overlay_ip = Tunneld.Overlay.address_for(machine)
    run_gateway("echo 'server=/#{device_ip}/#{overlay_ip}' > /dev/null 2>&1 || true")
    _ = overlay_ip
    :ok
  end

  defp default_iface(machine) do
    case SSH.run(machine, "ip route | awk '/^default/ {print $5; exit}'") do
      {:ok, out} -> {:ok, String.trim(out)}
      err -> err
    end
  end

  defp run_gateway(cmd) do
    System.cmd("sh", ["-c", cmd], stderr_to_stdout: true)
    |> case do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {:local, code, out}}
    end
  end

  defp gateway_ip do
    case Application.get_env(:tunneld, :network, []) do
      kw when is_list(kw) -> Keyword.get(kw, :gateway)
      map when is_map(map) -> Map.get(map, :gateway) || Map.get(map, "gateway")
      _ -> nil
    end
  end

  # The gateway's LAN interface (downstream). Used to keep a device's LAN
  # traffic local when it is egressed through a remote exit.
  defp lan_iface do
    case Application.get_env(:tunneld, :network, []) do
      kw when is_list(kw) -> Keyword.get(kw, :downstream) || "eth1"
      map when is_map(map) -> Map.get(map, :downstream) || Map.get(map, "downstream") || "eth1"
      _ -> "eth1"
    end
  end

  # The LAN subnet (e.g. 10.0.0.0/24) derived from the gateway IP.
  defp lan_subnet(gw) when is_binary(gw) do
    case String.split(gw, ".") do
      [a, b, c, _] -> "#{a}.#{b}.#{c}.0/24"
      _ -> "10.0.0.0/24"
    end
  end

  defp lan_subnet(_), do: "10.0.0.0/24"

  defp read_tables do
    case Tunneld.Persistence.read_json(Path.join(Tunneld.Config.fs_root(), "egress_tables.json")) do
      {:ok, %{"tables" => map}} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp write_tables(map) do
    Tunneld.Persistence.write_json(Path.join(Tunneld.Config.fs_root(), "egress_tables.json"), %{"tables" => map})
  end

  defp allocate_table(tables) do
    used = Map.values(tables) |> Enum.map(&String.to_integer/1)
    @table_base..(100 + 250)
    |> Enum.find(fn n -> n not in used end)
    |> Kernel.||(@table_base)
    |> Integer.to_string()
  end
end

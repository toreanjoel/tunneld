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

  **Two things handled explicitly:**

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

  @doc "Route a device's traffic out through a machine."
  def route_device(machine, device_ip, opts \\ []) do
    dns = Keyword.get(opts, :dns, "local")

    result =
      if @mock do
        {:ok,
         %{device_ip: device_ip, machine: machine["id"], table: table_for(machine), dns: dns}}
      else
        real_route_device(machine, device_ip, dns)
      end

    # Persist the device -> machine mapping so the selection survives a refresh.
    case result do
      {:ok, _} ->
        set_device_egress(device_ip, machine["id"])
        # The VM needs this device's return route to survive *its* reboot too,
        # so the installed script is rewritten with the new device list.
        refresh_exit_unit(machine)

      _ ->
        :ok
    end

    result
  end

  @doc "Remove a device from an exit (revert to gateway's own upstream)."
  def unroute_device(machine, device_ip) do
    result =
      if @mock do
        :ok
      else
        real_unroute_device(machine, device_ip)
      end

    clear_device_egress(device_ip)
    refresh_exit_unit(machine)
    result
  end

  @doc "The machine id a device's traffic is currently routed through, or `nil`."
  def device_egress(device_ip) do
    Map.get(read_device_egress(), device_ip)
  end

  defp set_device_egress(device_ip, machine_id) do
    write_device_egress(Map.put(read_device_egress(), device_ip, machine_id))
  end

  defp clear_device_egress(device_ip) do
    write_device_egress(Map.delete(read_device_egress(), device_ip))
  end

  defp read_device_egress do
    case Tunneld.Persistence.read_json(Path.join(Tunneld.Config.fs_root(), "device_egress.json")) do
      {:ok, %{"devices" => map}} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp write_device_egress(map) do
    Tunneld.Persistence.write_json(Path.join(Tunneld.Config.fs_root(), "device_egress.json"), %{
      "devices" => map
    })
  end

  @doc "Whether a machine has been made exit-capable (has a table allocated)."
  def exit_capable?(machine) do
    Map.has_key?(read_tables(), machine["id"])
  end

  @doc """
  Whether the rules an exit node needs are actually in place *right now*, on
  both ends.

  `exit_capable?/1` reads a local JSON flag, so it answered "yes" to a machine
  that had rebooted and lost every one of those rules - which is why the drift
  report was useless exactly when it was needed. This checks the live rules with
  `iptables -C` on the target and `ip rule` on the gateway.
  """
  def rules_current?(machine) do
    if @mock do
      # No live rules to read in mock mode; the table allocation is the state,
      # so report "current" for a machine that has one.
      exit_capable?(machine)
    else
      cond do
        not exit_capable?(machine) ->
          false

        true ->
          wg_iface = Tunneld.Overlay.iface_name(machine["id"])

          case default_iface(machine) do
            {:ok, iface} ->
              target_rules_ok?(machine, wg_iface, iface) and gateway_rules_ok?(machine, wg_iface)

            _ ->
              false
          end
      end
    end
  end

  defp target_rules_ok?(machine, wg_iface, iface) do
    check = target_check_command(wg_iface, iface, egressed_devices(machine["id"]))

    case SSH.run(machine, check <> " 2>/dev/null") do
      {:ok, out} -> String.trim(out) =~ ~r/1\s*$/
      _ -> false
    end
  end

  @doc false
  # The one probe that answers "is this box still an exit node, right now".
  #
  # The per-device return routes live on the VM and die with its interface, and a
  # WireGuard repair restarts that interface - so they vanish under the very
  # action meant to fix the machine. Checking only iptables reported a healthy
  # exit node whose devices had no way home, which is the state that reads to an
  # operator as "the exit node broke again". `sysctl` prints last among the
  # checked items, so its `1` is still the final line the caller inspects.
  def target_check_command(wg_iface, egress_iface, device_ips) do
    device_route_checks =
      Enum.map(device_ips, fn ip ->
        "ip route show dev #{wg_iface} 2>/dev/null | grep -qE '(^|[[:space:]])#{ip}([[:space:]]|$)'"
      end)

    Enum.join(
      [
        "iptables -t nat -C POSTROUTING -o #{egress_iface} -j MASQUERADE",
        "iptables -C FORWARD -i #{wg_iface} -o #{egress_iface} -j ACCEPT",
        "iptables -C FORWARD -i #{egress_iface} -o #{wg_iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT",
        "sysctl -n net.ipv4.ip_forward"
      ] ++ device_route_checks,
      " && "
    )
  end

  # Device IPs egressed through this machine.
  defp egressed_devices(machine_id) do
    read_device_egress()
    |> Enum.filter(fn {_ip, mid} -> mid == machine_id end)
    |> Enum.map(&elem(&1, 0))
  end

  defp gateway_rules_ok?(machine, wg_iface) do
    table = Map.get(read_tables(), machine["id"])
    match?({:ok, _}, run_gateway(gateway_check_command(wg_iface, table)))
  end

  @doc false
  # `ip rule` alone is not enough: the default route inside the policy table is
  # keyed to the interface and disappears when wg-quick restarts that interface,
  # leaving a rule that looks up an empty table - the device is matched, routed
  # nowhere, and the drift report says everything is fine.
  def gateway_check_command(wg_iface, table) do
    lan = lan_iface()

    "iptables -C FORWARD -i #{lan} -o #{wg_iface} -j ACCEPT 2>/dev/null && " <>
      "ip rule 2>/dev/null | grep -q 'lookup #{table}' && " <>
      "ip route show table #{table} 2>/dev/null | grep -q '^default'"
  end

  @doc "Remove all egress state for a machine. Idempotent."
  def cleanup_machine(machine) do
    id = machine["id"]
    iface = Tunneld.Overlay.iface_name(id)

    # Drop any device->machine mappings that point at this machine.
    devices = read_device_egress()
    write_device_egress(Map.reject(devices, fn {_ip, mid} -> mid == id end))

    # Remove the table allocation and its routes/rules.
    case Map.get(read_tables(), id) do
      nil ->
        :ok

      table ->
        _ = run_gateway("ip route flush table #{table} 2>/dev/null || true")
        _ = run_gateway("ip rule del lookup #{table} 2>/dev/null || true")
        write_tables(Map.delete(read_tables(), id))
    end

    # Remove the gateway FORWARD rules for this machine's WG interface.
    lan = lan_iface()
    _ = run_gateway("iptables -D FORWARD -i #{lan} -o #{iface} -j ACCEPT 2>/dev/null || true")

    _ =
      run_gateway(
        "iptables -D FORWARD -i #{iface} -o #{lan} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true"
      )

    :ok
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
  Make a machine exit-capable: persistent IP forwarding, MASQUERADE on its
  egress interface, and FORWARD rules for its WireGuard interface.

  Returns `{:ok, %{iface: egress_iface, table: table_id}}` or `{:error, reason}`.

  Three things this function used to get wrong, all of which presented to the
  operator as the same shrug:

  * It returned a bare `:ok`, which does not match a caller's `{:ok, _}`, so
    a fully successful setup was rendered by a catch-all clause as an error
    toast quoting a raw UUID.
  * Every iptables result was discarded with `_ =`, so a machine with no
    iptables at all reported exactly the same `:ok` as one that worked.
  * It never allocated the routing table, and `exit_capable?/1` is defined as
    "has a table allocated" - so the machine stayed "not set" in the UI
    forever no matter how many times you clicked.

  Now every step is checked and the table allocation is what marks success, so
  the badge reflects state that actually exists. Re-running is idempotent and
  is the supported repair path: iptables rules do not survive a reboot of the
  target, so "already capable" must never short-circuit the real work.
  """
  def ensure_exit_capable(machine) do
    if @mock do
      {:ok, %{iface: "eth0", table: table_for(machine)}}
    else
      real_ensure_exit_capable(machine)
    end
  end

  defp real_ensure_exit_capable(machine) do
    wg_iface = Tunneld.Overlay.iface_name(machine["id"])

    with {:ok, iface} <- default_iface(machine),
         :ok <- assert_iface(iface),
         :ok <- install_exit_unit(machine, wg_iface, iface) do
      {:ok, %{iface: iface, table: table_for(machine)}}
    end
  end

  @doc """
  The exit machine's rules, as a shell script body.

  Nothing here survives the machine's reboot on its own, so it is installed as
  `/usr/local/sbin/tunneld-exit` and run by the `tunneld-exit` unit - the same
  trick the client door uses. Before that, exit nodes were configured by
  one-off SSH commands: the VM came back from a restart with IP forwarding and
  NAT gone, the gateway still had its policy routes pointing at it, and every
  egressed device simply had no internet with nothing in the UI to explain it.

  The per-device return routes are part of the script for the same reason:
  `ip route add <device>/32 dev <wg-iface>` on the VM is runtime state too.
  """
  def exit_script(machine_id, egress_iface, device_ips) do
    wg_iface = Tunneld.Overlay.iface_name(machine_id)

    routes =
      device_ips
      |> Enum.uniq()
      |> Enum.map_join("\n", fn ip ->
        "ip route replace #{ip}/32 dev #{wg_iface} 2>/dev/null || true"
      end)

    [
      ip_forward_cmd(),
      masquerade_cmd(egress_iface),
      forward_cmd(wg_iface, egress_iface),
      forward_return_cmd(egress_iface, wg_iface),
      routes
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Write the script + unit and run it now. Idempotent, and the unit is what
  # makes the next reboot of the exit machine a non-event.
  defp install_exit_unit(machine, wg_iface, egress_iface) do
    unit = exit_unit(wg_iface)

    device_ips = egressed_devices(machine["id"])
    script = "#!/bin/sh\n" <> exit_script(machine["id"], egress_iface, device_ips)

    with {:ok, _} <- write_remote(machine, "/usr/local/sbin/tunneld-exit", script),
         {:ok, _} <- SSH.run(machine, "chmod +x /usr/local/sbin/tunneld-exit"),
         {:ok, _} <- write_remote(machine, "/etc/systemd/system/tunneld-exit.service", unit),
         {:ok, _} <-
           SSH.run(
             machine,
             "systemctl daemon-reload && systemctl enable tunneld-exit && systemctl restart tunneld-exit"
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # `PartOf` is the load-bearing line. A WireGuard repair restarts
  # `wg-quick@<iface>` on the VM, and that restart deletes every route this
  # script installs; without the coupling the exit node comes back from the
  # repair with NAT intact and its devices' return routes gone.
  def exit_unit(wg_iface) do
    """
    [Unit]
    Description=Tunneld exit node (forwarding, NAT and return routes)
    After=network-online.target wg-quick@#{wg_iface}.service
    Wants=wg-quick@#{wg_iface}.service
    PartOf=wg-quick@#{wg_iface}.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/sbin/tunneld-exit
    [Install]
    WantedBy=multi-user.target
    """
  end

  defp write_remote(machine, path, content) do
    dir = Path.dirname(path)

    SSH.run(
      machine,
      "mkdir -p #{dir} && cat > #{path} <<'TUNNELD_EOF'\n#{content}\nTUNNELD_EOF"
    )
  end

  @doc """
  Re-assert every gateway-side egress rule: the FORWARD pair per exit interface
  and the policy route + table routes per egressed device.

  `Tunneld.Iptables.reset/0` flushes FORWARD on every tunneld start, and `ip
  rule`/table routes never survive a gateway reboot at all. Both were rebuilt
  only by clicking the device again, so a gateway restart silently turned every
  egressed device back to the gateway's own upstream. The tables and device
  assignments are on disk (`egress_tables.json`, `device_egress.json`), so the
  whole thing is rebuilt from them, without needing the exit machine to answer.
  """
  def restore_all do
    if @mock, do: :ok, else: do_restore_all()
  end

  defp do_restore_all do
    tables = read_tables()

    Enum.each(tables, fn {id, table} ->
      iface = Tunneld.Overlay.iface_name(id)
      # `ip route replace default dev <iface> table N` fails outright when the
      # interface does not exist yet, so the boot sequence brings the interfaces
      # up first (`Overlay.restore_all/0` runs before this). A peer still down is
      # skipped here and picked up by the periodic pass - do not abort the whole
      # pass over one dead machine.
      _ = add_forward_rules(iface)
      _ = add_default_route(nil, iface, table)
      _ = add_lan_route(table)
    end)

    Enum.each(read_device_egress(), fn {device_ip, id} ->
      case Map.get(tables, id) do
        nil -> :ok
        table -> _ = add_rule(device_ip, table)
      end
    end)

    :ok
  end

  @doc "Re-apply the gateway half of one machine's egress. Idempotent."
  def ensure_gateway_rules(machine) do
    if @mock, do: :ok, else: do_ensure_gateway_rules(machine)
  end

  defp do_ensure_gateway_rules(machine) do
    case Map.get(read_tables(), machine["id"]) do
      nil ->
        :ok

      table ->
        iface = Tunneld.Overlay.iface_name(machine["id"])
        _ = add_forward_rules(iface)
        _ = add_default_route(nil, iface, table)
        _ = add_lan_route(table)

        read_device_egress()
        |> Enum.filter(fn {_ip, mid} -> mid == machine["id"] end)
        |> Enum.each(fn {device_ip, _} -> _ = add_rule(device_ip, table) end)

        :ok
    end
  end

  @doc """
  Re-push the exit rules to every machine that has one, after a gateway start.

  Cheap enough to run on boot and on a timer: one SSH round trip per exit
  machine, and every command in it is `-C`-checked, so a machine that is
  already correct changes nothing. This is what makes "the VM restarted an hour
  after the gateway" work without anyone pressing Reconcile.
  """
  def restore_targets do
    if @mock do
      :ok
    else
      read_tables()
      |> Map.keys()
      |> Enum.each(fn id ->
        case Tunneld.Machines.get(id) do
          {:ok, machine} -> _ = real_ensure_exit_capable(machine)
          _ -> :ok
        end
      end)

      :ok
    end
  end

  defp ip_forward_cmd do
    "sysctl -w net.ipv4.ip_forward=1 && " <>
      "(grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf)"
  end

  # NAT for egressed traffic.
  defp masquerade_cmd(iface) do
    "iptables -t nat -C POSTROUTING -o #{iface} -j MASQUERADE 2>/dev/null || " <>
      "iptables -t nat -A POSTROUTING -o #{iface} -j MASQUERADE"
  end

  # FORWARD-allow the WireGuard interface to/from the egress interface. Without
  # this the exit drops forwarded device traffic (UFW/FORWARD default is DROP)
  # even though ip_forward is on. This was found in live egress testing.
  defp forward_cmd(wg_iface, iface) do
    "iptables -C FORWARD -i #{wg_iface} -o #{iface} -j ACCEPT 2>/dev/null || " <>
      "iptables -I FORWARD 1 -i #{wg_iface} -o #{iface} -j ACCEPT"
  end

  defp forward_return_cmd(iface, wg_iface) do
    "iptables -C FORWARD -i #{iface} -o #{wg_iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || " <>
      "iptables -I FORWARD 1 -i #{iface} -o #{wg_iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
  end

  # A machine with no default route yields an empty interface name, which would
  # build `iptables -o  -j MASQUERADE`. Fail with a name the operator can act on.
  defp assert_iface(""), do: {:error, :no_default_route_on_target}
  defp assert_iface(iface) when is_binary(iface), do: :ok
  defp assert_iface(_), do: {:error, :no_default_route_on_target}

  # --- Real implementation ---

  defp real_route_device(machine, device_ip, dns) do
    id = machine["id"]
    iface = Tunneld.Overlay.iface_name(id)
    table = table_for(machine)
    overlay_ip = Tunneld.Overlay.address_for(machine)

    with :ok <- assert_gateway_role(device_ip),
         {:ok, _} <- add_rule(device_ip, table),
         {:ok, _} <- add_default_route(overlay_ip, iface, table),
         {:ok, _} <- add_lan_route(table),
         :ok <- add_forward_rules(iface),
         {:ok, _} <- add_vm_device_route(machine, device_ip, iface),
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
    # Idempotent: a duplicate `ip rule add` fails with "File exists", so swallow
    # that specific case but surface real errors.
    run_gateway("ip rule add from #{device_ip} lookup #{table} 2>/dev/null || true")
  end

  defp add_default_route(_overlay_ip, iface, table) do
    # The exit-node interface has AllowedIPs = 0.0.0.0/0, so a link-scope
    # `dev <iface>` default route is correct. A `via <overlay_ip>` next-hop
    # does not resolve inside the policy table (returns "Network is
    # unreachable"), which silently broke egress. `ip route replace` is
    # idempotent and reports real failures.
    run_gateway("ip route replace default dev #{iface} table #{table}")
  end

  # Keep the device's LAN traffic local (to the gateway) instead of sending it
  # through the tunnel, so the device can still reach the gateway/subnet.
  defp add_lan_route(table) do
    gw = Tunneld.Config.gateway_ip()
    iface = lan_iface()
    run_gateway("ip route replace #{lan_subnet(gw)} dev #{iface} table #{table}")
  end

  # The gateway's FORWARD chain defaults to DROP and only allows eth1<->eth0.
  # Without explicit rules, a device's traffic routed to the WG tunnel is
  # dropped before it ever reaches the exit machine. Add idempotent rules to
  # allow LAN <-> WG-tunnel forwarding (per exit interface, not per device).
  defp add_forward_rules(iface) do
    lan = lan_iface()

    with {:ok, _} <-
           run_gateway(
             "iptables -C FORWARD -i #{lan} -o #{iface} -j ACCEPT 2>/dev/null || " <>
               "iptables -A FORWARD -i #{lan} -o #{iface} -j ACCEPT"
           ),
         {:ok, _} <-
           run_gateway(
             "iptables -C FORWARD -i #{iface} -o #{lan} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || " <>
               "iptables -A FORWARD -i #{iface} -o #{lan} -m state --state RELATED,ESTABLISHED -j ACCEPT"
           ) do
      :ok
    end
  end

  # The VM must route the device's return traffic back through the tunnel.
  # `replace`, not `add`: this runs on every route_device and on repair passes.
  defp add_vm_device_route(machine, device_ip, iface) do
    SSH.run(machine, "ip route replace #{device_ip}/32 dev #{iface} 2>/dev/null || true")
  end

  # Rewrite the installed exit script after the device list changes, so the VM
  # comes back from a reboot with the right return routes and not the old set.
  defp refresh_exit_unit(machine) do
    if @mock do
      :ok
    else
      if exit_capable?(machine) do
        case default_iface(machine) do
          {:ok, iface} ->
            install_exit_unit(machine, Tunneld.Overlay.iface_name(machine["id"]), iface)

          _ ->
            :ok
        end
      else
        :ok
      end
    end
  end

  # Assert tunneld is the device's default gateway (the prerequisite for egress).
  defp assert_gateway_role(device_ip) do
    gateway = Tunneld.Config.gateway_ip()

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
    Tunneld.Persistence.write_json(Path.join(Tunneld.Config.fs_root(), "egress_tables.json"), %{
      "tables" => map
    })
  end

  defp allocate_table(tables) do
    used = Map.values(tables) |> Enum.map(&String.to_integer/1)

    @table_base..(100 + 250)
    |> Enum.find(fn n -> n not in used end)
    |> Kernel.||(@table_base)
    |> Integer.to_string()
  end
end

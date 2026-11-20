defmodule Tunneld.Overlay do
  @moduledoc """
  WireGuard peering that makes remote machines local.

  The core idea: **WireGuard makes remote machines local.** The gateway sits
  behind NAT and often moves; VMs have stable public IPs. So the gateway
  *dials out* to each managed machine over WireGuard, giving every machine an
  overlay IP that tunneld can route to. Once a machine is a peer, `location`
  collapses to a hint used by a single function, `address_for/1`:

      local  machine -> LAN IP (same subnet as the gateway)
      remote machine -> overlay IP (over the WireGuard tunnel)

  Topology notes:

  * One interface per machine: `wg-<machine_id>`, brought up via `wg-quick`.
  * The gateway dials out, so it sets `PersistentKeepalive = 25`.
  * **`Table = off` on every interface.** Tunneld installs all routes by
    hand. This is what prevents a routing loop (a VM's public endpoint must
    never resolve through its own tunnel) and is a prerequisite for egress
    (§4.5), where multiple peers share `AllowedIPs = 0.0.0.0/0`.

  Key handling: the keypair for a machine is generated **on the gateway**; only
  the target's half is pushed over SSH. The gateway's private key is stored
  mode 0600 under `TUNNELD_DATA/wg/`. Private keys are never logged, rendered,
  or returned from the API.

  In mock mode no real WireGuard is configured; `address_for/1` returns the
  machine's own address so the flow runs on a laptop.
  """

  alias Tunneld.Machines.SSH

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @gateway_overlay_ip Application.compile_env(:tunneld, :overlay_gateway_ip, "10.88.0.1")
  # Per-machine overlay interfaces listen on 51821 (the existing wgtest overlay
  # already uses 51820 on the gateway/VM).
  @wg_port Application.compile_env(:tunneld, :overlay_port, 51_821)

  @doc "The gateway's own overlay IP - the address managed machines dial back to."
  def gateway_overlay_ip, do: @gateway_overlay_ip

  @doc "The machine overlay range, e.g. `10.88.0.0/24`."
  def overlay_subnet_value do
    [a, b, c, _] = String.split(@gateway_overlay_ip, ".")
    "#{a}.#{b}.#{c}.0/24"
  end

  @doc """
  Generate a WireGuard keypair as `{public, private}`.

  Shared with `Tunneld.Clients`: one implementation of the temp-file dance
  around `wg pubkey`, which has already been the source of one collision bug.
  """
  def gen_keypair, do: do_gen_keypair()

  @doc "Return the address to reach a machine: LAN IP or overlay IP."
  def address_for(machine) do
    if same_subnet?(machine["address"]) do
      machine["address"]
    else
      overlay_ip_for(machine)
    end
  end

  @doc "Ensure a machine is a WireGuard peer. Idempotent."
  def ensure_peer(machine) do
    if @mock do
      {:ok, %{overlay_ip: mock_overlay_ip(machine)}}
    else
      real_ensure_peer(machine)
    end
  end

  @doc """
  Remove a machine's WireGuard peer config and bring the interface down.

  Callers that must not block on a dead host should use `remove_peer_local/1`
  and `remove_peer_remote/1` directly - see `Tunneld.Machines.remove/1`.
  """
  def remove_peer(machine) do
    remove_peer_local(machine)
    remove_peer_remote(machine)
    :ok
  end

  @doc "Remove a machine's overlay IP allocation (called on disenroll/delete)."
  def remove_overlay_ip(machine) do
    map = overlay_ips() |> Map.delete(machine["id"])

    Tunneld.Persistence.write_json(Path.join(Tunneld.Config.fs_root(), "overlay.json"), %{
      "peers" => map
    })

    :ok
  end

  @doc "Parsed `wg show` status for a machine: handshake age, tx/rx bytes."
  def status(machine) do
    if @mock do
      {:ok, %{interface: iface_name(machine["id"]), handshake: nil, tx: 0, rx: 0, up: false}}
    else
      real_status(machine)
    end
  end

  # Stable mock overlay IP derived from the machine id (last octet from the
  # uuid hash) so address_for is deterministic within a session.
  defp mock_overlay_ip(machine) do
    octet = machine["id"] |> String.to_charlist() |> Enum.sum() |> rem(250)
    "10.88.0.#{octet + 2}"
  end

  defp real_ensure_peer(machine) do
    id = machine["id"]
    iface = iface_name(id)

    with {:ok, target_pub} <- exchange_keys(machine),
         :ok <- install_target(machine, target_pub, iface),
         {:ok, _} <- configure_gateway(machine, target_pub, iface) do
      # A machine re-enrolled under a new id leaves its old interface behind on
      # the target, and a stale config can claim this machine's overlay address:
      # wg-quick then fails the real interface with "Address already in use" and
      # the tunnel never comes back after a reboot. Seen live on 139.84.235.70 on
      # 2026-11-20, where four abandoned configs held the host's overlay addrs.
      _ = prune_target(machine)
      {:ok, %{overlay_ip: overlay_ip_for(machine)}}
    end
  end

  @doc """
  Move the target's WireGuard configs that belong to no machine tunneld knows
  about on that host into `/root/tunneld-stale-wireguard/`, disabling their units.

  Only names this tool generates (`wg-<8 hex>`) are considered; anything an
  operator made by hand is left running.
  """
  def prune_target(machine) do
    if @mock do
      []
    else
      ours =
        Tunneld.Machines.list()
        |> Enum.filter(&(&1["address"] == machine["address"]))
        |> Enum.map(&iface_name(&1["id"]))
        |> MapSet.new()

      case SSH.run(machine, "ls /etc/wireguard 2>/dev/null") do
        {:ok, out} ->
          out
          |> String.split("\n", trim: true)
          |> Enum.map(&String.replace_suffix(&1, ".conf", ""))
          |> Enum.filter(&Regex.match?(~r/^wg-[0-9a-f]{8}$/, &1))
          |> Enum.reject(&MapSet.member?(ours, &1))
          |> Enum.map(fn iface ->
            _ =
              SSH.run(
                machine,
                "systemctl disable --now wg-quick@#{iface} 2>/dev/null || true; " <>
                  "wg-quick down #{iface} 2>/dev/null || true; " <>
                  "mkdir -p /root/tunneld-stale-wireguard && " <>
                  "mv /etc/wireguard/#{iface}.conf /root/tunneld-stale-wireguard/ 2>/dev/null || true"
              )

            iface
          end)

        _ ->
          []
      end
    end
  end

  # Gateway keypair for a machine, persisted mode 0600. Returns
  # {gateway_public_key, target_public_key}.
  defp exchange_keys(machine) do
    id = machine["id"]
    iface = iface_name(id)
    priv_path = Path.join([Tunneld.Config.fs_root(), "wg", id])
    File.mkdir_p!(Path.dirname(priv_path))

    {gw_pub, _gw_priv} =
      if File.exists?(priv_path) do
        {File.read!(priv_path <> ".pub") |> String.trim(), File.read!(priv_path)}
      else
        {gpub, gpriv} = do_gen_keypair()
        File.write!(priv_path, gpriv)
        File.chmod!(priv_path, 0o600)
        File.write!(priv_path <> ".pub", gpub <> "\n")
        {gpub, gpriv}
      end

    # The target's keypair is generated on the gateway and kept here (the
    # private half mode 0600), so re-running is genuinely idempotent. Generating
    # a fresh pair every time meant every Sync rotated the keys on both ends, and
    # if only one end picked the new pair up the tunnel could never handshake.
    {t_pub, t_priv} =
      if File.exists?(priv_path <> ".target") do
        {File.read!(priv_path <> ".target.pub") |> String.trim(),
         File.read!(priv_path <> ".target") |> String.trim()}
      else
        {tpub, tpriv} = do_gen_keypair()
        File.write!(priv_path <> ".target", tpriv)
        File.chmod!(priv_path <> ".target", 0o600)
        File.write!(priv_path <> ".target.pub", tpub <> "\n")
        {tpub, tpriv}
      end

    gw_overlay_ip = @gateway_overlay_ip

    # PostUp, not a one-off SSH command: this is the rule that lets the gateway
    # reach the machine again after *its* reboot, and a plain `iptables -I` was
    # gone by the next boot. wg-quick runs it every time the interface comes up,
    # and both halves are idempotent.
    post_up =
      "ip route replace #{gw_overlay_ip}/32 dev #{iface_name(id)} 2>/dev/null || true; " <>
        "iptables -C INPUT -p udp --dport #{@wg_port} -j ACCEPT 2>/dev/null || " <>
        "iptables -I INPUT 1 -p udp --dport #{@wg_port} -j ACCEPT 2>/dev/null || true"

    target_conf = """
    [Interface]
    Address = #{overlay_ip_for(machine)}/32
    PrivateKey = #{t_priv}
    ListenPort = #{@wg_port}
    Table = off
    PostUp = #{post_up}

    [Peer]
    PublicKey = #{gw_pub}
    AllowedIPs = 0.0.0.0/0
    """

    with :ok <- write_remote(machine, "/etc/wireguard/#{iface}.conf", target_conf) do
      {:ok, t_pub}
    end
  end

  defp install_target(machine, target_pub, iface) do
    _ = target_pub
    # Install wireguard-tools if missing (apt/dnf/apk), so wg-quick exists.
    run(
      machine,
      "command -v wg-quick >/dev/null 2>&1 || " <>
        "(command -v apt-get >/dev/null 2>&1 && apt-get update -qq && apt-get install -y -qq wireguard-tools) || " <>
        "(command -v dnf >/dev/null 2>&1 && dnf install -y wireguard-tools) || " <>
        "(command -v apk >/dev/null 2>&1 && apk add wireguard-tools) || true"
    )

    # Enable the wg-quick service so the peer survives the target's reboot, and
    # *restart* it rather than `enable --now`: `--now` is a no-op on a unit that
    # is already active, so the freshly written config (with a new keypair) sat
    # on disk while the running interface kept its old key. The gateway then
    # listed a peer the target no longer had, and no amount of clicking
    # Reconcile could close the gap - which is what made a reboot look like the
    # machine had to be removed and re-enrolled.
    run(
      machine,
      "systemctl enable wg-quick@#{iface} 2>/dev/null || true; " <>
        "systemctl restart wg-quick@#{iface} 2>/dev/null || " <>
        "(wg-quick down #{iface} 2>/dev/null; wg-quick up #{iface}) 2>/dev/null || true"
    )

    # Open the overlay port on the target's firewall (ufw or iptables) so the
    # gateway's dial-out handshake can reach it.
    run(
      machine,
      "ufw allow #{@wg_port}/udp 2>/dev/null || " <>
        "iptables -I INPUT 1 -p udp --dport #{@wg_port} -j ACCEPT 2>/dev/null || true"
    )

    :ok
  end

  defp configure_gateway(machine, target_pub, iface) do
    id = machine["id"]
    overlay_ip = overlay_ip_for(machine)
    gw_priv = File.read!(Path.join([Tunneld.Config.fs_root(), "wg", id]))

    # The gateway dials out to the target, so the peer needs the target's
    # endpoint (public IP for remote, LAN IP for local) on the WG port.
    endpoint = "#{machine["address"]}:#{@wg_port}"

    gw_conf = """
    [Interface]
    Address = #{@gateway_overlay_ip}/32
    PrivateKey = #{gw_priv}
    Table = off
    # replace, never add: if a stale interface still holds this /32 (the gateway
    # accumulates wg-* configs for machines that were removed), `add` fails with
    # "File exists", `|| true` hides it, and the machine comes back from a reboot
    # with its tunnel handshaking but no route to it - exactly the reported
    # "restart breaks the VMs". Seen live on the gateway on 2026-11-20 for
    # 10.88.0.5, where the route belonged to a removed machine's interface.
    PostUp = ip route replace #{overlay_ip}/32 dev #{iface} 2>/dev/null || true

    [Peer]
    PublicKey = #{String.trim(target_pub)}
    # 0.0.0.0/0 so the gateway can pass egressed device traffic through the
    # tunnel (the per-machine overlay is point-to-point; Table=off keeps the
    # gateway's own routing on eth0).
    AllowedIPs = 0.0.0.0/0
    Endpoint = #{endpoint}
    PersistentKeepalive = 25
    """

    write_gateway("/etc/wireguard/#{iface}.conf", gw_conf)

    # Same reason as the target side: enable for the next boot, restart so the
    # config just written is the one actually running.
    run_gateway(
      "systemctl enable wg-quick@#{iface} 2>/dev/null || true; " <>
        "systemctl restart wg-quick@#{iface} 2>/dev/null || " <>
        "(wg-quick down #{iface} 2>/dev/null; wg-quick up #{iface}) 2>/dev/null || true"
    )
  end

  @doc """
  Bring the gateway's per-machine overlay interfaces up after a gateway reboot.

  The units are enabled, so systemd normally does this. It does not do it if the
  interface was left up-but-associatingless, or if tunneld's iptables reset ran
  first and an operator has since edited a config, so the interfaces are
  restarted once at boot and their PostUp routes re-asserted.

  Configs belonging to machines that no longer exist are moved aside first. Each
  per-machine interface carries a route for its peer's overlay IP, so an orphaned
  interface can be holding that /32 when the real interface comes up: the tunnel
  handshakes, the route never lands, and the machine looks enrolled but
  unreachable. Seen live on the gateway on 2026-11-20, where 10.88.0.5 was
  claimed by an interface for a machine removed months earlier - and by a manual
  test tunnel claiming the whole 10.88.0.0/24.
  """
  def restore_all do
    if @mock do
      :ok
    else
      live = Tunneld.Machines.list() |> Enum.map(&iface_name(&1["id"]))

      prune_orphans(live)

      Enum.each(live, fn iface ->
        _ =
          run_gateway(
            "systemctl restart wg-quick@#{iface} 2>/dev/null || " <>
              "(wg-quick down #{iface} 2>/dev/null; wg-quick up #{iface}) 2>/dev/null || true"
          )
      end)

      :ok
    end
  end

  @doc """
  Take WireGuard configs that belong to no enrolled machine out of the running
  set. Moved to `backup/wireguard-<date>/` under the data dir and their units
  disabled - never deleted, so a config can be put back by hand.

  `wg-clients` is the shared client door and is left alone, as is any config
  whose name is not one this gateway generated.
  """
  def prune_orphans(live_ifaces) do
    if @mock do
      []
    else
      live = MapSet.new(live_ifaces ++ ["wg-clients"])
      ours = ~r/^wg-[0-9a-f]{8}$/

      generated_ifaces()
      |> Enum.filter(&Regex.match?(ours, &1))
      |> Enum.reject(&MapSet.member?(live, &1))
      |> Enum.map(fn iface ->
        dest =
          Path.join([
            Tunneld.Config.fs_root(),
            "backup",
            "wireguard-#{Date.utc_today() |> Date.to_iso8601()}"
          ])

        File.mkdir_p!(dest)

        _ =
          run_gateway(
            "systemctl disable --now wg-quick@#{iface} 2>/dev/null || true; " <>
              "wg-quick down #{iface} 2>/dev/null || true"
          )

        case File.exists?("/etc/wireguard/#{iface}.conf") do
          true ->
            _ = File.rename("/etc/wireguard/#{iface}.conf", Path.join(dest, "#{iface}.conf"))
            iface

          false ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  # Every wg-*.conf on the gateway, as interface names.
  defp generated_ifaces do
    Path.wildcard("/etc/wireguard/wg-*.conf")
    |> Enum.map(&(&1 |> Path.basename() |> String.replace_suffix(".conf", "")))
  end

  @doc """
  Tear down the gateway's half of a peer. Local only, so it always completes.

  Split from the remote half because the two used to run in one function that
  SSHed to the target *first*. Deleting a machine that was already gone meant
  that call blocked on the SSH connect timeout, the caller's teardown budget
  expired, the task was brutal-killed, and the gateway's own interface, route
  and key were left behind - which is how a gateway ends up with WireGuard
  interfaces for machines that no longer exist.
  """
  def remove_peer_local(machine) do
    if @mock, do: :ok, else: real_remove_peer_local(machine)
  end

  defp real_remove_peer_local(machine) do
    id = machine["id"]
    iface = iface_name(id)
    _ = run_gateway("systemctl disable --now wg-quick@#{iface} 2>/dev/null || true")
    _ = run_gateway("wg-quick down #{iface} 2>/dev/null || true")
    _ = run_gateway("ip link del #{iface} 2>/dev/null || true")
    File.rm(Path.join([Tunneld.Config.fs_root(), "wg", id]))
    File.rm(Path.join([Tunneld.Config.fs_root(), "wg", id <> ".pub"]))
    File.rm(Path.join([Tunneld.Config.fs_root(), "wg", id <> ".target"]))
    File.rm(Path.join([Tunneld.Config.fs_root(), "wg", id <> ".target.pub"]))
    File.rm("/etc/wireguard/#{iface}.conf")
    :ok
  end

  @doc "Tear down the target's half. Best-effort: the host may be gone."
  def remove_peer_remote(machine) do
    if @mock, do: :ok, else: real_remove_peer_remote(machine)
  end

  defp real_remove_peer_remote(machine) do
    iface = iface_name(machine["id"])
    _ = run(machine, "systemctl disable --now wg-quick@#{iface} 2>/dev/null || true")

    # The units the machine was told to keep running at boot: exit NAT and the
    # client door. Leaving them means a disenrolled machine keeps forwarding (or
    # DNAT-ing 51822) forever, with nothing on the gateway able to turn it off.
    _ =
      run(
        machine,
        "systemctl disable --now wg-quick@#{iface} 2>/dev/null || true; " <>
          "wg-quick down #{iface} 2>/dev/null || true; " <>
          "rm -f /etc/wireguard/#{iface}.conf; " <>
          "systemctl disable --now tunneld-exit 2>/dev/null || true; " <>
          "systemctl disable --now tunneld-door 2>/dev/null || true; " <>
          "rm -f /usr/local/sbin/tunneld-exit /usr/local/sbin/tunneld-door " <>
          "/etc/systemd/system/tunneld-exit.service /etc/systemd/system/tunneld-door.service; " <>
          "systemctl daemon-reload 2>/dev/null || true"
      )

    :ok
  end

  defp real_status(machine) do
    id = machine["id"]

    case run_gateway("wg show #{iface_name(id)} 2>/dev/null") do
      {:ok, ""} -> {:ok, %{interface: iface_name(id), up: false, handshake: nil, tx: 0, rx: 0}}
      {:ok, out} -> parse_wg_show(out, iface_name(id))
      err -> err
    end
  end

  defp parse_wg_show(out, iface) do
    peer =
      out
      |> String.split("peer:", parts: 2)
      |> List.last()
      |> String.split("\n")
      |> Enum.find(fn l -> String.contains?(l, "latest handshake") end)

    handshake =
      if peer do
        peer |> String.split(":", parts: 2) |> List.last() |> String.trim()
      else
        nil
      end

    {:ok, %{interface: iface, up: handshake != nil, handshake: handshake, tx: 0, rx: 0}}
  end

  @doc "WireGuard interface name for a machine. wg-quick caps names at 15 chars,\n  so use a short hash of the machine id rather than the full UUID."
  def iface_name(id) do
    short = :crypto.hash(:sha256, id) |> Base.encode16(case: :lower) |> String.slice(0, 8)
    "wg-#{short}"
  end

  defp do_gen_keypair do
    {priv, 0} = System.cmd("wg", ["genkey"], stderr_to_stdout: true)
    priv = String.trim(priv)

    # System.cmd has no :input option; pipe the private key to `wg pubkey`
    # via a temp file so the public half can be derived.
    # Unique per call (unique_integer can collide across two rapid calls in the
    # same process, which would make `wg pubkey` read the wrong/removed file).
    nonce = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    tmp = Path.join(System.tmp_dir!(), "wg_key_#{System.unique_integer([:positive])}_#{nonce}")
    File.write!(tmp, priv <> "\n")
    File.chmod!(tmp, 0o600)
    {pub, 0} = System.cmd("sh", ["-c", "wg pubkey < #{tmp}"], stderr_to_stdout: true)
    File.rm(tmp)

    {String.trim(pub), priv}
  end

  defp overlay_ip_for(machine) do
    # Persisted mapping machine_id -> overlay IP. Allocate on first use.
    case overlay_ips()[machine["id"]] do
      nil ->
        ip = allocate_overlay_ip()
        put_overlay_ip(machine["id"], ip)
        ip

      ip ->
        ip
    end
  end

  defp overlay_ips do
    case Tunneld.Persistence.read_json(Path.join(Tunneld.Config.fs_root(), "overlay.json")) do
      {:ok, %{"peers" => map}} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp put_overlay_ip(id, ip) do
    map = overlay_ips() |> Map.put(id, ip)

    Tunneld.Persistence.write_json(Path.join(Tunneld.Config.fs_root(), "overlay.json"), %{
      "peers" => map
    })
  end

  defp allocate_overlay_ip do
    used = Map.values(overlay_ips())

    2..254
    |> Enum.find(fn n -> "10.88.0.#{n}" not in used end)
    |> then(&"10.88.0.#{&1}")
  end

  defp same_subnet?(address) do
    gw = Tunneld.Config.gateway_ip()

    with {:ok, a} <- parse_ip4(address),
         {:ok, g} <- parse_ip4(gw) do
      match?({[x, y, z, _], [x, y, z, _]}, {a, g})
    else
      _ -> false
    end
  end

  defp parse_ip4(str) do
    case :inet.parse_address(String.to_charlist(str)) do
      {:ok, {a, b, c, d}} -> {:ok, [a, b, c, d]}
      _ -> :error
    end
  end

  defp run(machine, command) do
    SSH.run(machine, command)
  end

  defp run_gateway(command) do
    # The gateway runs tunneld; shell out locally.
    System.cmd("sh", ["-c", command], stderr_to_stdout: true)
    |> case do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {:local, code, out}}
    end
  end

  defp write_remote(machine, path, content) do
    # Write a file on the target via a heredoc over SSH (no SCP dependency).
    # Create the parent dir first: the target may not have /etc/wireguard yet.
    dir = Path.dirname(path)

    cmd =
      "mkdir -p #{dir} && cat > #{path} <<'TUNNELD_EOF'\n#{content}\nTUNNELD_EOF\nchmod 600 #{path}"

    case run(machine, cmd) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  defp write_gateway(path, content) do
    File.write!(path, content)
    File.chmod!(path, 0o600)
    :ok
  end
end

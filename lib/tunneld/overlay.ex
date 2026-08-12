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

  Topology notes (see TODO §4.4):

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

  @doc "Remove a machine's WireGuard peer config and bring the interface down. Idempotent."
  def remove_peer(machine) do
    if @mock do
      :ok
    else
      real_remove_peer(machine)
    end
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
      {:ok, %{overlay_ip: overlay_ip_for(machine)}}
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

    # Generate a keypair for the target; push its private half + the gateway's
    # public half over SSH; return the target's public half.
    {t_pub, t_priv} = do_gen_keypair()

    gw_overlay_ip = @gateway_overlay_ip

    target_conf = """
    [Interface]
    Address = #{overlay_ip_for(machine)}/32
    PrivateKey = #{t_priv}
    ListenPort = #{@wg_port}
    Table = off
    PostUp = ip route add #{gw_overlay_ip}/32 dev #{iface_name(id)} 2>/dev/null || true

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

    # Enable + start the wg-quick service for this peer (config file is
    # /etc/wireguard/<iface>.conf, so the unit is wg-quick@<iface>).
    run(machine, "systemctl enable --now wg-quick@#{iface} 2>/dev/null || true")
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
    PostUp = ip route add #{overlay_ip}/32 dev #{iface} 2>/dev/null || true

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
    run_gateway("systemctl enable --now wg-quick@#{iface} 2>/dev/null || true")
  end

  defp real_remove_peer(machine) do
    remove_peer_local(machine)
    remove_peer_remote(machine)
    :ok
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
    id = machine["id"]
    iface = iface_name(id)
    _ = run_gateway("systemctl disable --now wg-quick@#{iface} 2>/dev/null || true")
    _ = run_gateway("wg-quick down #{iface} 2>/dev/null || true")
    _ = run_gateway("ip link del #{iface} 2>/dev/null || true")
    File.rm(Path.join([Tunneld.Config.fs_root(), "wg", id]))
    File.rm(Path.join([Tunneld.Config.fs_root(), "wg", id <> ".pub"]))
    File.rm("/etc/wireguard/#{iface}.conf")
    :ok
  end

  @doc "Tear down the target's half. Best-effort: the host may be gone."
  def remove_peer_remote(machine) do
    iface = iface_name(machine["id"])
    _ = run(machine, "systemctl disable --now wg-quick@#{iface} 2>/dev/null || true")
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

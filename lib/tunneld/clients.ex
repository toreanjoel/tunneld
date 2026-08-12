defmodule Tunneld.Clients do
  @moduledoc """
  WireGuard peers for people, as opposed to `Tunneld.Overlay`'s peers for
  machines.

  A client is a phone or laptop that should reach the home subnet from
  anywhere. It gets its own keypair and an address in the client range, and it
  **always terminates on the gateway** - never on a VPS.

  That last choice is the whole design:

      at home   client -> 10.0.0.1:51822                      (one hop, no VPS)
      away      client -> <vps>:51822 -DNAT-> 10.88.0.1:51822 (VPS is a door)

  A managed machine forwards the port straight into the tunnel it already
  holds with the gateway (`ensure_door/1`), so it never sees a client key,
  never runs a second WireGuard instance, and can be swapped for a closer one
  without reissuing anything. Same keypair, same address, same peer identity
  in both places - only `Endpoint` differs.

  ## Keys

  The keypair is generated on the gateway, like machine enrolment. The
  client's **private key is returned exactly once**, in the config it needs,
  and is never written to disk. `Overlay`'s rule that private keys are never
  rendered cannot hold here - the client cannot connect without it - so the
  rule becomes: shown once, stored never, and re-issued by revoking and
  enrolling again.

  ## What this module does not do

  It grants no access to the LAN on its own. A client can reach the overlay
  and nothing else until a scope is added, because the gateway's FORWARD chain
  is `DROP`. Client-side `AllowedIPs` is routing, not a boundary - the client
  owns that file - so anything that matters is enforced here.
  """

  alias Tunneld.{Config, Persistence}

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @iface "wg-clients"
  @port Application.compile_env(:tunneld, :client_port, 51_822)
  @subnet "10.88.1"
  @gateway_ip "10.88.1.1"
  @conf_path "/etc/wireguard/wg-clients.conf"

  @doc "The UDP port clients dial, on the gateway and on any machine door."
  def port, do: @port

  @doc "The gateway's address inside the client range."
  def gateway_ip, do: @gateway_ip

  @doc "Clients enrolled against a machine."
  def for_machine(machine_id),
    do: Enum.filter(list(), &(&1["machine_id"] == machine_id))

  @doc "Revoke every client belonging to a machine. Called when it is removed."
  def revoke_for_machine(machine_id) do
    machine_id |> for_machine() |> Enum.each(&revoke(&1["id"]))
    :ok
  end

  @doc "All enrolled clients, newest first."
  def list do
    read()
    |> Map.values()
    |> Enum.sort_by(& &1["created_at"], :desc)
  end

  @doc "One client by id, or nil."
  def get(id), do: Map.get(read(), id)

  @doc """
  Enrol a client and return `{:ok, client, config}`.

  `config` is the full WireGuard config text and is the **only** time the
  private key exists outside the client's device.

  A client belongs to the machine it dials through, so `:machine` is how you
  enrol one and removing that machine takes its clients with it. The tunnel
  still terminates on the gateway - the machine is only a door - but tying the
  two together keeps one list per machine instead of a global pool of peers
  pointing at addresses that may no longer exist.
  """
  def enroll(name, opts \\ []) when is_binary(name) do
    try do
      do_enroll(String.trim(name), opts)
    catch
      {:door, reason} -> {:error, {:door_failed, reason}}
    end
  end

  defp do_enroll(name, opts) do
    if name == "" do
      {:error, :name_required}
    else
      {pub, priv} = gen_keypair()
      id = uuid()

      machine = Keyword.get(opts, :machine)

      # Set the machine up as a door here rather than only at enrolment. It is
      # idempotent and it is the moment the door is actually needed, so a
      # machine added before this feature existed - or one whose rules were
      # lost - is fixed by the act of adding a client, with no separate repair
      # step to remember. If it fails, no client is issued: handing over a
      # config that cannot connect is worse than refusing.
      case machine && ensure_door(machine) do
        {:error, reason} -> throw({:door, reason})
        _ -> :ok
      end

      client = %{
        "id" => id,
        "name" => name,
        "public_key" => pub,
        "address" => allocate_address(),
        "machine_id" => machine && machine["id"],
        "machine_name" => machine && machine["name"],
        "endpoint" =>
          (machine && machine["address"]) || Keyword.get(opts, :endpoint) || @gateway_ip,
        "lan_access" => Keyword.get(opts, :lan_access, []),
        "created_at" => now()
      }

      with :ok <- put(id, client),
           :ok <- sync() do
        {:ok, client, config_for(client, priv)}
      end
    end
  end

  @doc "Remove a client's peer and its record. Idempotent."
  def revoke(id) do
    case get(id) do
      nil ->
        :ok

      client ->
        write(Map.delete(read(), id))
        _ = clear_lan_rules(client)
        sync()
    end
  end

  @doc """
  Replace a client's LAN scope: `[]` for overlay-only, or a list of LAN IPs.

  Enforced with FORWARD rules on the gateway, because the client's own config
  is not a boundary.
  """
  def set_lan_access(id, ips) when is_list(ips) do
    case get(id) do
      nil ->
        {:error, :not_found}

      client ->
        _ = clear_lan_rules(client)
        updated = Map.put(client, "lan_access", ips)
        put(id, updated)
        _ = apply_lan_rules(updated)
        {:ok, updated}
    end
  end

  @doc "The config text a client needs. Private key is supplied, never stored."
  def config_for(client, private_key) do
    """
    # No DNS line, deliberately. The phone applies whatever is named here as its
    # system resolver for as long as the tunnel is up, so naming a resolver that
    # does not answer takes the whole device offline - dnsmasq here is bound
    # with `interface=eth1` and ignores queries arriving on the client
    # interface. Leaving it out keeps the phone on its own resolver and the
    # internet working. The cost is that *.tunneld.lan names do not resolve for
    # clients; use addresses, or the dashboard at #{@gateway_ip}.
    [Interface]
    PrivateKey = #{private_key}
    Address = #{client["address"]}/32
    # Two WireGuard layers on the away path (this tunnel inside the gateway's
    # tunnel to the machine), so keep clear of the 1500-byte ceiling.
    MTU = 1360

    [Peer]
    PublicKey = #{gateway_public_key()}
    Endpoint = #{client["endpoint"]}:#{@port}
    AllowedIPs = #{allowed_ips(client)}
    PersistentKeepalive = 25
    """
  end

  @doc """
  An SVG QR of a client config, for scanning into the phone app.

  Three things a QR needs that are easy to get wrong on a dark dashboard:

  * **Dark modules on a light background.** Inverting it looks better against
    the panel and most scanners refuse to read it.
  * **Few enough modules to resolve on screen.** Every character raises the
    version and shrinks each module, so comments are stripped here - the copy
    box keeps them, the QR does not need to carry 130 bytes of prose.
  * **A quiet zone.** The generated SVG has no margin; the caller must sit it
    on white padding or scanners will not find the finder patterns.
  """
  def qr_svg(config) when is_binary(config) do
    config
    |> qr_payload()
    |> EQRCode.encode()
    |> EQRCode.svg(width: 320, background_color: "#FFFFFF", color: "#000000")
  end

  @doc "The config with comments and blank lines removed, as encoded in the QR."
  def qr_payload(config) do
    config
    |> String.split("\n")
    |> Enum.reject(&(String.starts_with?(String.trim(&1), "#") or String.trim(&1) == ""))
    |> Enum.join("\n")
  end

  @doc """
  Make a machine a door: forward the client port into the tunnel it already
  holds with the gateway.

  The machine never terminates a client session - it rewrites the destination
  and the packet continues inside the existing overlay - so no key material
  and no second WireGuard instance ever land on it. Persisted as a unit
  because the target's iptables do not survive its reboot.
  """
  def ensure_door(machine) do
    if @mock, do: :ok, else: real_ensure_door(machine)
  end

  @doc """
  The rules a door needs, as a shell script. Also the body of the unit.

  The SNAT line is not optional. With DNAT alone the gateway would see the
  client's real public address and reply to it **directly out its own uplink**,
  so the client would get an answer from an address it never wrote to and its
  NAT would drop it - a tunnel that looks configured on both ends and never
  completes a handshake. Masquerading makes the gateway answer the machine,
  which un-NATs and returns it down the path the client actually used.

  `ip_forward` is set here too rather than relying on `Egress`: a door is
  useful on a machine that was never made an exit node.
  """
  def door_script do
    gw = Tunneld.Overlay.gateway_overlay_ip()

    """
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

    iptables -t nat -C PREROUTING -p udp --dport #{@port} -j DNAT --to-destination #{gw}:#{@port} 2>/dev/null || \\
      iptables -t nat -A PREROUTING -p udp --dport #{@port} -j DNAT --to-destination #{gw}:#{@port}

    iptables -t nat -C POSTROUTING -d #{gw} -p udp --dport #{@port} -j MASQUERADE 2>/dev/null || \\
      iptables -t nat -A POSTROUTING -d #{gw} -p udp --dport #{@port} -j MASQUERADE

    iptables -C FORWARD -p udp --dport #{@port} -j ACCEPT 2>/dev/null || \\
      iptables -I FORWARD 1 -p udp --dport #{@port} -j ACCEPT
    """
  end

  # --- gateway interface ---

  @doc "Rewrite the gateway's client interface from the current peer list."
  def sync do
    if @mock, do: write_mock(), else: real_sync()
  end

  @doc "The gateway interface config, from all enrolled clients."
  def build_conf do
    peers =
      list()
      |> Enum.map_join("\n", fn c ->
        """

        [Peer]
        # #{c["name"]}
        PublicKey = #{c["public_key"]}
        AllowedIPs = #{c["address"]}/32
        """
      end)

    """
    [Interface]
    Address = #{@gateway_ip}/24
    ListenPort = #{@port}
    PrivateKey = #{gateway_private_key()}
    Table = off
    PostUp = ip route add #{@subnet}.0/24 dev #{@iface} 2>/dev/null || true
    #{peers}
    """
  end

  # --- internals ---

  # AllowedIPs always covers the LAN, regardless of what the client is allowed
  # to reach. It is baked into the config the moment it is issued, so scoping it
  # per client would mean re-issuing and re-scanning every time access changed -
  # and granting access to a device the phone has no route for does nothing at
  # all, which is exactly how the first version failed. Routing here, permission
  # on the gateway.
  defp allowed_ips(_client) do
    Enum.join(
      [Tunneld.Overlay.overlay_subnet_value(), "#{@subnet}.0/24", lan_subnet()],
      ", "
    )
  end

  defp lan_subnet do
    case String.split(Config.gateway_ip() || "10.0.0.1", ".") do
      [a, b, c, _] -> "#{a}.#{b}.#{c}.0/24"
      _ -> "10.0.0.0/24"
    end
  end

  defp real_sync do
    File.mkdir_p!(Path.dirname(@conf_path))
    File.write!(@conf_path, build_conf())
    File.chmod!(@conf_path, 0o600)

    unit = "wg-quick@#{@iface}"
    _ = sh("systemctl enable #{unit} 2>/dev/null || true")

    case sh("systemctl restart #{unit}") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:wg_clients_reload_failed, reason}}
    end
  end

  defp write_mock do
    dir = Path.join(Config.fs_root(), "clients")
    File.mkdir_p!(dir)
    File.write(Path.join(dir, "wg-clients.conf"), build_conf())
    :ok
  end

  defp real_ensure_door(machine) do
    unit = """
    [Unit]
    Description=Tunneld client door (forwards UDP #{@port} into the overlay)
    After=network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/sbin/tunneld-door
    [Install]
    WantedBy=multi-user.target
    """

    script = "#!/bin/sh\nset -e\n" <> door_script()

    with {:ok, _} <- write_remote(machine, "/usr/local/sbin/tunneld-door", script),
         {:ok, _} <- Tunneld.Machines.SSH.run(machine, "chmod +x /usr/local/sbin/tunneld-door"),
         {:ok, _} <- write_remote(machine, "/etc/systemd/system/tunneld-door.service", unit),
         # `enable --now` will not re-run a Type=oneshot unit that is already
         # active with RemainAfterExit, so an updated script would be written
         # and never applied. Restart forces it, and re-running is idempotent.
         {:ok, _} <-
           Tunneld.Machines.SSH.run(
             machine,
             "systemctl daemon-reload && systemctl enable tunneld-door && " <>
               "systemctl restart tunneld-door"
           ),
         {:ok, _} <-
           Tunneld.Machines.SSH.run(
             machine,
             "ufw allow #{@port}/udp 2>/dev/null || " <>
               "iptables -I INPUT 1 -p udp --dport #{@port} -j ACCEPT 2>/dev/null || true"
           ) do
      :ok
    else
      {:error, reason} -> {:error, {:door_failed, reason}}
    end
  end

  defp apply_lan_rules(%{"lan_access" => ips, "address" => addr}) when is_list(ips) do
    lan = Config.network(:downstream) || "eth1"

    Enum.each(ips, fn ip ->
      sh(
        "iptables -C FORWARD -i #{@iface} -o #{lan} -s #{addr} -d #{ip} -j ACCEPT 2>/dev/null || " <>
          "iptables -I FORWARD 1 -i #{@iface} -o #{lan} -s #{addr} -d #{ip} -j ACCEPT"
      )
    end)

    sh(
      "iptables -C FORWARD -i #{lan} -o #{@iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || " <>
        "iptables -I FORWARD 1 -i #{lan} -o #{@iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
    )

    :ok
  end

  defp apply_lan_rules(_), do: :ok

  defp clear_lan_rules(%{"lan_access" => ips, "address" => addr}) when is_list(ips) do
    lan = Config.network(:downstream) || "eth1"

    Enum.each(ips, fn ip ->
      sh(
        "iptables -D FORWARD -i #{@iface} -o #{lan} -s #{addr} -d #{ip} -j ACCEPT 2>/dev/null || true"
      )
    end)

    :ok
  end

  defp clear_lan_rules(_), do: :ok

  defp gateway_private_key do
    path = Path.join([Config.fs_root(), "wg", "clients.key"])

    if File.exists?(path) do
      File.read!(path) |> String.trim()
    else
      {pub, priv} = gen_keypair()
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, priv)
      File.chmod!(path, 0o600)
      File.write!(path <> ".pub", pub <> "\n")
      priv
    end
  end

  defp gateway_public_key do
    _ = gateway_private_key()
    path = Path.join([Config.fs_root(), "wg", "clients.key.pub"])
    File.read!(path) |> String.trim()
  end

  defp allocate_address do
    used = read() |> Map.values() |> Enum.map(& &1["address"])

    2..254
    |> Enum.find(fn n -> "#{@subnet}.#{n}" not in used end)
    |> then(&"#{@subnet}.#{&1}")
  end

  defp gen_keypair do
    if @mock do
      n = :crypto.strong_rand_bytes(32) |> Base.encode64()
      {n, :crypto.strong_rand_bytes(32) |> Base.encode64()}
    else
      Tunneld.Overlay.gen_keypair()
    end
  end

  defp read do
    case Persistence.read_json(store_path()) do
      {:ok, %{"clients" => m}} when is_map(m) -> m
      _ -> %{}
    end
  end

  defp write(map), do: Persistence.write_json(store_path(), %{"clients" => map})

  defp put(id, client) do
    write(Map.put(read(), id, client))
    :ok
  end

  defp store_path, do: Path.join(Config.fs_root(), "clients.json")

  defp write_remote(machine, path, content) do
    Tunneld.Machines.SSH.run(
      machine,
      "mkdir -p #{Path.dirname(path)} && cat > #{path} <<'TUNNELD_EOF'\n#{content}\nTUNNELD_EOF"
    )
  end

  defp sh(cmd) do
    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {code, out}}
    end
  end

  defp uuid, do: UUID.uuid4()
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end

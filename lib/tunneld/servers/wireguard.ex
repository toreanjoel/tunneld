defmodule Tunneld.Servers.Wireguard do
  @moduledoc """
  Manages a per-user WireGuard VPN server (wg0).

  Brings the wg0 interface up/down on demand, generates the server keypair,
  manages peer lifecycles (create, list, revoke, regenerate config), and
  produces client .conf content for peers.

  In mock mode, all system commands are skipped and keypairs are generated
  using :crypto for testing without a WireGuard kernel module.
  """

  use GenServer
  require Logger

  alias Tunneld.Servers.Wireguard.ConfigGen

  @default_port 51820
  @interface "wg0"

  @pubsub Tunneld.PubSub
  @topic "component:wireguard"

  # --- Client API ---

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc """
  Enable the WireGuard VPN server.

  Generates a server keypair if not present, creates the wg0 interface,
  and assigns the server IP from the subnet. Accepts optional overrides:

    - `listen_port` — UDP port (default 51820)
    - `endpoint` — public IP or DDNS hostname for peer configs
    - `subnet` — user-peer pool in CIDR notation (e.g. "10.42.0.0/24")

  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  def enable_server(opts \\ %{}), do: GenServer.call(__MODULE__, {:enable_server, opts}, 30_000)

  @doc "Disable the WireGuard VPN server and tear down the wg0 interface."
  def disable_server, do: GenServer.call(__MODULE__, :disable_server, 30_000)

  @doc "Return the current WireGuard server state."
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @doc "Get the cached config text for a peer. Returns nil if not cached."
  def get_peer_config(peer_id), do: GenServer.call(__MODULE__, {:get_peer_config, peer_id})

  @doc "Reset GenServer to initial state (test helper)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @doc "Update the endpoint (public IP or DDNS hostname) used in peer configs."
  def set_endpoint(endpoint), do: GenServer.call(__MODULE__, {:set_endpoint, endpoint})

  @doc "Return the server IP address (e.g. \"10.42.0.1\")."
  def server_ip, do: GenServer.call(__MODULE__, :server_ip)

  @doc """
  Add a new peer to the VPN server.

  Generates a keypair, assigns the next available IP from the subnet,
  and adds the peer to the live interface. Returns `{:ok, peer, config}`
  where `config` is the client .conf content for download or QR display.
  The peer's private key is included in the config but NOT stored in state.
  """
  def add_peer(name, full_tunnel \\ false),
    do: GenServer.call(__MODULE__, {:add_peer, name, full_tunnel}, 15_000)

  @doc "Remove a peer by ID. Revokes access immediately on the live interface."
  def remove_peer(peer_id), do: GenServer.call(__MODULE__, {:remove_peer, peer_id}, 15_000)

  @doc """
  Regenerate the client config for a peer.

  Generates a new keypair, updates the peer on the live interface, and
  returns `{:ok, peer, config}` where `config` is the new client .conf.
  The old public key is replaced on the interface.
  """
  def regenerate_peer_config(peer_id),
    do: GenServer.call(__MODULE__, {:regenerate_peer_config, peer_id}, 15_000)

  # --- Server Callbacks ---

  @impl true
  def init(_) do
    state =
      case read_file() do
        {:ok, data} ->
          # Restore state from persisted data, add runtime-only fields
          data
          |> Map.put("mock?", mock?())
          |> Map.put_new("peer_configs", %{})
          |> maybe_reenable()

        _ ->
          initial_state()
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:get_peer_config, peer_id}, _from, state) do
    config = get_in(state, ["peer_configs", peer_id])
    {:reply, config, state}
  end

  @impl true
  def handle_call(:reset, _from, _state), do: {:reply, :ok, initial_state()}

  @impl true
  def handle_call(:server_ip, _from, state) do
    ip = if state["enabled"] and state["subnet"], do: subnet_to_server_ip(state["subnet"]), else: nil
    {:reply, ip, state}
  end

  @impl true
  def handle_call({:enable_server, opts}, _from, state) do
    if state["enabled"] do
      {:reply, {:ok, state}, state}
    else
      port = opts["listen_port"] || state["listen_port"] || @default_port
      subnet = state["subnet"] || opts["subnet"] || generate_subnet()

      with {:ok, private_key, public_key} <- ensure_keypair(state),
           :ok <- bring_up_interface(private_key, port, subnet),
           :ok <- apply_iptables_rules(port),
           :ok <- add_dnsmasq_wg_interface(),
           :ok <- readd_peers(state["peers"]),
           {:ok, endpoint} <- resolve_endpoint(opts, state) do
        new_state =
          state
          |> Map.put("enabled", true)
          |> Map.put("private_key", private_key)
          |> Map.put("public_key", public_key)
          |> Map.put("subnet", subnet)
          |> Map.put("listen_port", port)
          |> Map.put("endpoint", endpoint)

        persist(new_state)
        broadcast(new_state)
        notify(:info, "VPN server enabled")
        Logger.info("WireGuard VPN server enabled on :#{port}")
        {:reply, {:ok, new_state}, new_state}
      else
        {:error, reason} ->
          notify(:error, "Failed to enable VPN server: #{reason}")
          Logger.error("WireGuard enable failed: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:disable_server, _from, state) do
    if state["enabled"] do
      remove_iptables_rules(state["listen_port"])
      remove_dnsmasq_wg_interface()
      bring_down_interface()

      new_state = Map.put(state, "enabled", false)
      persist(new_state)
      broadcast(new_state)
      notify(:info, "VPN server disabled")
      Logger.info("WireGuard VPN server disabled")
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:set_endpoint, endpoint}, _from, state) do
    case validate_endpoint(endpoint) do
      :ok ->
        new_state = Map.put(state, "endpoint", endpoint)
        persist(new_state)
        broadcast(new_state)
        Logger.info("WireGuard endpoint set to #{endpoint}")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:add_peer, name, full_tunnel}, _from, state) do
    if not state["enabled"] do
      {:reply, {:error, :server_not_enabled}, state}
    else
      with {:ok, private_key, public_key} <- generate_keypair(),
           {:ok, ip} <- assign_ip(state) do
        peer_id = generate_id()

        peer = %{
          "id" => peer_id,
          "name" => name,
          "public_key" => public_key,
          "ip" => ip,
          "full_tunnel" => full_tunnel
        }

        case add_peer_to_interface(public_key, ip) do
          :ok ->
            # Build state first so we can generate config
            new_state =
              state
              |> Map.put("peers", Map.put(state["peers"], peer_id, peer))
              |> Map.put("next_ip", state["next_ip"] + 1)

            # Build full peer with private key for config generation
            full_peer = Map.put(peer, "private_key", private_key)
            config = ConfigGen.peer_conf(full_peer, new_state)

            # Cache config for QR re-view (runtime only, not persisted)
            new_state = put_in(new_state, ["peer_configs", peer_id], config)

            persist(new_state)
            broadcast(new_state)
            Logger.info("WireGuard peer added: #{name} (#{ip})")

            {:reply, {:ok, full_peer, config}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      else
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:remove_peer, peer_id}, _from, state) do
    case Map.get(state["peers"], peer_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      peer ->
        case remove_peer_from_interface(peer["public_key"]) do
          :ok ->
            new_state =
            state
            |> Map.put("peers", Map.delete(state["peers"], peer_id))
            |> update_in(["peer_configs"], &Map.delete(&1, peer_id))
            persist(new_state)
            broadcast(new_state)
            Logger.info("WireGuard peer removed: #{peer["name"]}")
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:regenerate_peer_config, peer_id}, _from, state) do
    case Map.get(state["peers"], peer_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      peer ->
        with {:ok, new_private_key, new_public_key} <- generate_keypair(),
             :ok <- replace_peer_on_interface(peer["public_key"], new_public_key, peer["ip"]) do
          updated_peer = Map.put(peer, "public_key", new_public_key)

          new_state =
            state
            |> Map.put("peers", Map.put(state["peers"], peer_id, updated_peer))

          full_peer = Map.put(updated_peer, "private_key", new_private_key)
          config = ConfigGen.peer_conf(full_peer, new_state)

          new_state = put_in(new_state, ["peer_configs", peer_id], config)

          persist(new_state)
          broadcast(new_state)
          Logger.info("WireGuard peer config regenerated: #{peer["name"]}")

          {:reply, {:ok, full_peer, config}, new_state}
        else
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  # --- Private: Interface Management ---

  defp bring_up_interface(private_key, port, subnet) do
    server_addr = subnet_to_server_ip(subnet)

    if mock?() do
      Logger.debug("[WireGuard MOCK] Bringing up #{@interface} on :#{port}")
      :ok
    else
      # Remove existing interface if present (idempotent)
      exec("ip", ["link", "del", @interface])

      key_path = write_private_key_temp(private_key)

      result =
        with {_, 0} <- exec("ip", ["link", "add", @interface, "type", "wireguard"]),
             {_, 0} <- exec("wg", ["set", @interface, "private-key", key_path, "listen-port", to_string(port)]),
             {_, 0} <- exec("ip", ["address", "add", server_addr, "dev", @interface]),
             {_, 0} <- exec("ip", ["link", "set", @interface, "mtu", "1280"]),
             {_, 0} <- exec("ip", ["link", "set", @interface, "up"]) do
          :ok
        else
          {out, code} ->
            exec("ip", ["link", "del", @interface])
            {:error, "Command failed (#{code}): #{out}"}
        end

      File.rm(key_path)
      result
    end
  end

  defp bring_down_interface do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Bringing down #{@interface}")
      :ok
    else
      case exec("ip", ["link", "del", @interface]) do
        {_, 0} -> :ok
        {out, code} -> {:error, "Command failed (#{code}): #{out}"}
      end
    end
  end

  defp add_peer_to_interface(public_key, ip) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Adding peer #{public_key} at #{ip}")
      :ok
    else
      case exec("wg", ["set", @interface, "peer", public_key, "allowed-ips", "#{ip}/32"]) do
        {_, 0} -> :ok
        {out, code} -> {:error, "Command failed (#{code}): #{out}"}
      end
    end
  end

  defp remove_peer_from_interface(public_key) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Removing peer #{public_key}")
      :ok
    else
      case exec("wg", ["set", @interface, "peer", public_key, "remove"]) do
        {_, 0} -> :ok
        {out, code} -> {:error, "Command failed (#{code}): #{out}"}
      end
    end
  end

  defp replace_peer_on_interface(old_public_key, new_public_key, ip) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Replacing peer #{old_public_key} -> #{new_public_key}")
      :ok
    else
      with {_, 0} <- exec("wg", ["set", @interface, "peer", old_public_key, "remove"]),
           {_, 0} <- exec("wg", ["set", @interface, "peer", new_public_key, "allowed-ips", "#{ip}/32"]) do
        :ok
      else
        {out, code} -> {:error, "Command failed (#{code}): #{out}"}
      end
    end
  end

  # --- Private: Keypair Generation ---

  defp ensure_keypair(state) do
    case {state["private_key"], state["public_key"]} do
      {nil, nil} -> generate_keypair()
      {priv, pub} -> {:ok, priv, pub}
    end
  end

  defp generate_keypair do
    if mock?() do
      private_key = :crypto.strong_rand_bytes(32) |> Base.encode64()
      public_key = :crypto.strong_rand_bytes(32) |> Base.encode64()
      {:ok, private_key, public_key}
    else
      case exec("wg", ["genkey"]) do
        {private_key, 0} ->
          private_key = String.trim(private_key)
          key_path = write_private_key_temp(private_key)

          result =
            case exec("sh", ["-c", "wg pubkey < #{key_path}"]) do
              {public_key, 0} ->
                {:ok, private_key, String.trim(public_key)}

              {out, code} ->
                {:error, "wg pubkey failed (#{code}): #{out}"}
            end

          File.rm(key_path)
          result

        {out, code} ->
          {:error, "wg genkey failed (#{code}): #{out}"}
      end
    end
  end

  defp write_private_key_temp(private_key) do
    path = Path.join(System.tmp_dir!(), "wg0_pk_#{:erlang.unique_integer([:positive])}")

    File.write!(path, private_key)
    File.chmod!(path, 0o600)
    path
  end

  # --- Private: Subnet / IP ---

  defp generate_subnet do
    second = :rand.uniform(254)
    third = :rand.uniform(254)
    "10.#{second}.#{third}.0/24"
  end

  defp subnet_to_server_ip(subnet) do
    [prefix, mask] = String.split(subnet, "/")
    [a, b, c, _d] = String.split(prefix, ".")
    "#{a}.#{b}.#{c}.1/#{mask}"
  end

  defp assign_ip(state) do
    subnet = state["subnet"]

    if is_nil(subnet) do
      {:error, :no_subnet}
    else
      next = state["next_ip"]
      [prefix, _mask] = String.split(subnet, "/")
      [a, b, c, _d] = String.split(prefix, ".")
      {:ok, "#{a}.#{b}.#{c}.#{next}"}
    end
  end

  # --- Private: Endpoint ---

  defp resolve_endpoint(opts, state) do
    cond do
      opts["endpoint"] ->
        case validate_endpoint(opts["endpoint"]) do
          :ok -> {:ok, opts["endpoint"]}
          error -> error
        end

      state["endpoint"] ->
        {:ok, state["endpoint"]}

      true ->
        auto_detect_endpoint()
    end
  end

  defp validate_endpoint(endpoint) when is_binary(endpoint) do
    cond do
      String.contains?(endpoint, "\n") ->
        {:error, "endpoint must not contain newlines"}

      String.contains?(endpoint, "\r") ->
        {:error, "endpoint must not contain carriage returns"}

      String.trim(endpoint) != endpoint ->
        {:error, "endpoint must not have leading/trailing whitespace"}

      String.length(endpoint) == 0 ->
        {:error, "endpoint must not be empty"}

      # IPv4:port or hostname:port or bare IPv4/hostname (port added later)
      true ->
        :ok
    end
  end

  defp validate_endpoint(_), do: {:error, "endpoint must be a string"}

  defp auto_detect_endpoint do
    if mock?() do
      {:ok, "mock.endpoint.tunneld.local"}
    else
      case exec("curl", ["-s", "--max-time", "5", "ifconfig.me"]) do
        {ip, 0} ->
          ip = String.trim(ip)

          cond do
            Regex.match?(~r/^\d{1,3}(\.\d{1,3}){3}$/, ip) ->
              {:ok, ip}

            Regex.match?(~r/^[0-9a-fA-F:]+$/, ip) and String.contains?(ip, ":") ->
              {:ok, ip}

            true ->
              {:error, "Could not auto-detect public IP (got: #{ip})"}
          end

        _ ->
          {:error, "Could not auto-detect public IP"}
      end
    end
  end

  # --- Private: Helpers ---

  defp generate_id do
    :erlang.unique_integer([:positive]) |> Integer.to_string()
  end

  defp exec(cmd, args) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] #{cmd} #{Enum.join(args, " ")}")
      {"", 0}
    else
      System.cmd(cmd, args, stderr_to_stdout: true)
    end
  end

  defp broadcast(state) do
    safe_state = Map.drop(state, ["private_key"])

    if pubsub_running?() do
      Phoenix.PubSub.broadcast(@pubsub, @topic, %{
        id: "wireguard_server",
        module: TunneldWeb.Live.Components.Wireguard.Server,
        data: safe_state
      })

      Phoenix.PubSub.broadcast(@pubsub, @topic, %{
        id: "wireguard_peers",
        module: TunneldWeb.Live.Components.Wireguard.Peers,
        data: safe_state
      })
    end
  end

  defp notify(type, message) do
    if pubsub_running?() do
      Phoenix.PubSub.broadcast(@pubsub, "notifications", %{type: type, message: message})
    end
  end

  defp pubsub_running? do
    Process.whereis(@pubsub) != nil
  end

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  # --- Private: Persistence ---

  defp path do
    root = Tunneld.Config.fs(:root)
    wireguard = Tunneld.Config.fs(:wireguard)
    if root && wireguard, do: Path.join(root, wireguard), else: nil
  end

  defp read_file do
    case path() do
      p when is_binary(p) -> Tunneld.Persistence.read_json(p)
      _ -> {:error, :no_path_configured}
    end
  end

  defp write_file(data) do
    case path() do
      p when is_binary(p) -> Tunneld.Persistence.write_json(p, data)
      _ -> {:error, :no_path_configured}
    end
  end

  defp do_file_exists? do
    case path() do
      p when is_binary(p) -> File.exists?(p)
      _ -> false
    end
  end

  @doc "Check if the WireGuard configuration file exists."
  def file_exists?, do: do_file_exists?()

  @doc "Get the path to the WireGuard configuration file."
  def path?, do: path()

  defp persist(state) do
    # Strip runtime-only fields before writing to disk
    state
    |> Map.drop(["mock?", "peer_configs"])
    |> write_file()
  end

  # --- Private: Re-enable on Restart ---

  defp maybe_reenable(state) do
    if state["enabled"] do
      Logger.info("WireGuard was enabled at shutdown, re-enabling interface")

      private_key = state["private_key"]
      port = state["listen_port"]
      subnet = state["subnet"]

      case bring_up_interface(private_key, port, subnet) do
        :ok ->
          # Re-add all persisted peers to the interface
          readd_peers(state["peers"])
          # Re-apply iptables rules
          apply_iptables_rules(port)
          # Re-add wg0 interface to dnsmasq
          add_dnsmasq_wg_interface()
          Logger.info("WireGuard interface re-enabled with #{map_size(state["peers"])} peer(s)")
          state

        {:error, reason} ->
          Logger.error("WireGuard re-enable failed: #{inspect(reason)}")
          Map.put(state, "enabled", false)
      end
    else
      state
    end
  end

  defp readd_peers(peers) when is_map(peers) do
    Enum.each(peers, fn {_id, peer} ->
      case add_peer_to_interface(peer["public_key"], peer["ip"]) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Failed to re-add peer #{peer["name"]}: #{reason}")
      end
    end)
  end

  defp readd_peers(_), do: :ok

  # --- Private: Iptables ---

  defp apply_iptables_rules(port) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Applying iptables rules")
      :ok
    else
      Tunneld.Iptables.wireguard_up(port)
    end
  end

  defp remove_iptables_rules(port) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Removing iptables rules")
      :ok
    else
      Tunneld.Iptables.wireguard_down(port)
    end
  end

  # --- Private: Dnsmasq ---

  @wg_dnsmasq_conf "/etc/dnsmasq.d/tunneld_wireguard.conf"

  defp add_dnsmasq_wg_interface do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Adding wg0 to dnsmasq")
      :ok
    else
      File.write!(@wg_dnsmasq_conf, "interface=wg0\n")
      reload_dnsmasq()
      Logger.info("Added wg0 interface to dnsmasq")
      :ok
    end
  end

  defp remove_dnsmasq_wg_interface do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Removing wg0 from dnsmasq")
      :ok
    else
      if File.exists?(@wg_dnsmasq_conf) do
        File.rm!(@wg_dnsmasq_conf)
        reload_dnsmasq()
        Logger.info("Removed wg0 interface from dnsmasq")
      end

      :ok
    end
  end

  defp reload_dnsmasq do
    Tunneld.Servers.Services.restart_service(:dnsmasq, :no_notify)
  end

  # --- Private: Initial State ---

  defp initial_state do
    %{
      "enabled" => false,
      "public_key" => nil,
      "private_key" => nil,
      "listen_port" => @default_port,
      "endpoint" => nil,
      "subnet" => nil,
      "peers" => %{},
      "peer_configs" => %{},
      "next_ip" => 2,
      "mock?" => mock?()
    }
  end
end
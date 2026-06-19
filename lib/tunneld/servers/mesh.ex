defmodule Tunneld.Servers.Mesh do
  @moduledoc """
  Manages connection to the tunneld-relay coordinator.
  """

  use GenServer
  require Logger

  alias Tunneld.Servers.{Wireguard, Devices, DeviceTags}

  @pubsub Tunneld.PubSub
  @topic "component:mesh"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_state, do: GenServer.call(__MODULE__, :get_state)
  def sync_now, do: GenServer.cast(__MODULE__, :sync_now)
  def reconfigure, do: GenServer.cast(__MODULE__, :reconfigure)

  @impl true
  def init(_) do
    config = load_persisted_config()

    enabled = Keyword.get(config, :enabled, false)
    coordinator_url = Keyword.get(config, :coordinator_url)
    token = Keyword.get(config, :token)
    node_name = Keyword.get(config, :node_name, "")
    poll_interval = Keyword.get(config, :poll_interval, 25_000)

    state = %{
      enabled: enabled and is_binary(coordinator_url) and is_binary(token),
      coordinator_url: coordinator_url,
      token: token,
      node_name: node_name,
      poll_interval: poll_interval,
      wg_mtu: Keyword.get(config, :wg_mtu, 1280),
      node_id: nil,
      relay_pubkey: nil,
      relay_endpoint: nil,
      mesh_ip: nil,
      peers: %{},
      last_sync: nil,
      last_geo: %{},
      status: if(enabled, do: :connecting, else: :disabled),
      allowed_ips: [],
      backoff: 5000,
      timer_ref: nil
    }

    if state.enabled do
      node_id = load_or_create_node_id()
      state = %{state | node_id: node_id}
      Wireguard.ensure_keypair()
      send(self(), :init_mesh)
      {:ok, state}
    else
      if enabled and (not is_binary(coordinator_url) or not is_binary(token)) do
        Logger.warning("Mesh enabled but coordinator_url or token missing - mesh idle")
      else
        Logger.info("Mesh disabled")
      end

      {:ok, %{state | status: :disabled}}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:sync_now, state) do
    if state.enabled and state.status != :disabled do
      cancel_timer(state.timer_ref)
      send(self(), :do_poll)
      {:noreply, %{state | timer_ref: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:reconfigure, state) do
    cancel_timer(state.timer_ref)

    if state.enabled do
      Tunneld.Iptables.remove_mesh_forwarding()
      Wireguard.bring_down_mesh()
    end

    config = load_persisted_config()

    enabled = Keyword.get(config, :enabled, false)
    coordinator_url = Keyword.get(config, :coordinator_url)
    token = Keyword.get(config, :token)
    node_name = Keyword.get(config, :node_name, "")
    poll_interval = Keyword.get(config, :poll_interval, 25_000)

    wg_mtu = Keyword.get(config, :wg_mtu, 1280)

    should_enable = enabled and is_binary(coordinator_url) and is_binary(token)

    new_state = %{
      state
      | enabled: should_enable,
        coordinator_url: coordinator_url,
        token: token,
        node_name: node_name,
        poll_interval: poll_interval,
        wg_mtu: wg_mtu,
        status: if(should_enable, do: :connecting, else: :disabled),
        relay_pubkey: nil,
        relay_endpoint: nil,
        mesh_ip: nil,
        peers: %{},
        allowed_ips: [],
        backoff: 5000,
        last_sync: nil,
        last_geo: %{}
    }

    if should_enable do
      node_id = load_or_create_node_id()
      new_state = %{new_state | node_id: node_id}
      Wireguard.ensure_keypair()
      broadcast(new_state)
      send(self(), :init_mesh)
      {:noreply, new_state}
    else
      if enabled and (not is_binary(coordinator_url) or not is_binary(token)) do
        Logger.warning("Mesh enabled but coordinator_url or token missing - mesh idle")
      end

      disabled_state = %{new_state | node_id: nil}
      broadcast(disabled_state)
      {:noreply, disabled_state}
    end
  end

  @impl true
  def handle_info(:init_mesh, state) do
    if not state.enabled do
      {:noreply, %{state | status: :disabled}}
    else
      case setup_mesh(state) do
      {:ok, new_state} ->
        Tunneld.Iptables.add_mesh_forwarding()
        cancel_timer(new_state.timer_ref)
        ref = Process.send_after(self(), :do_poll, new_state.poll_interval)
        connected_state = %{new_state | timer_ref: ref, status: :connected, backoff: 5000}
        broadcast(connected_state)
        {:noreply, connected_state}

      {:error, reason} ->
        Logger.warning("Mesh setup failed: #{inspect(reason)} - retrying in #{state.backoff}ms")
        ref = Process.send_after(self(), :init_mesh, state.backoff)
        new_backoff = min(state.backoff * 2, 60_000)
        error_state = %{state | timer_ref: ref, status: :relay_unreachable, backoff: new_backoff}
        broadcast(error_state)
        {:noreply, error_state}
      end
    end
  end

  @impl true
  def handle_info(:do_poll, state) do
    if not state.enabled do
      {:noreply, state}
    else
      new_state =
        case do_poll(state) do
          {:ok, s} ->
            cancel_timer(s.timer_ref)
            ref = Process.send_after(self(), :do_poll, s.poll_interval)
            %{s | timer_ref: ref, status: :connected, backoff: 5000}

          {:error, reason, s} ->
            Logger.warning("Mesh poll failed: #{inspect(reason)} - retrying in #{s.backoff}ms")
            cancel_timer(s.timer_ref)
            ref = Process.send_after(self(), :do_poll, s.backoff)
            new_backoff = min(s.backoff * 2, 60_000)
            %{s | timer_ref: ref, status: :relay_unreachable, backoff: new_backoff}
        end

      broadcast(new_state)
      {:noreply, new_state}
    end
  end

  defp setup_mesh(state) do
    pubkey = Wireguard.get_public_key()

    if is_nil(pubkey) do
      {:error, :no_public_key}
    else
      with :ok <- Wireguard.bring_up_mesh(state.wg_mtu),
           {:ok, mesh_ip} <- register_with_relay(state, pubkey, state.node_name, state.allowed_ips),
           :ok <- Wireguard.assign_mesh_ip(mesh_ip),
           {:ok, hub} <- fetch_hub(state),
           :ok <- configure_relay_peer(hub) do
        Tunneld.Geolocation.refresh()
        allowed_ips = [mesh_ip <> "/32"]

        {:ok,
         %{
           state
           | relay_pubkey: hub["relay_pubkey"],
             relay_endpoint: hub["relay_endpoint"],
             mesh_ip: mesh_ip,
             allowed_ips: allowed_ips,
             last_sync: DateTime.utc_now()
         }}
      end
    end
  end

  defp do_poll(state) do
    with :ok <- post_heartbeat(state),
         new_allowed_ips <- recalculate_allowed_ips(state),
         state2 <- maybe_reregister(state, new_allowed_ips),
         {:ok, peers} <- fetch_peers(state2),
         state3 <- update_mesh_peers(state2, peers) do
      {:ok, %{state3 | peers: peers, last_sync: DateTime.utc_now()}}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp post_heartbeat(state) do
    url = "#{state.coordinator_url}/heartbeat"

    case HTTPoison.post(url, Jason.encode!(%{node_id: state.node_id}), headers(state)) do
      {:ok, %{status_code: 200}} -> :ok
      {:ok, %{status_code: 404}} -> {:error, :node_not_found}
      {:ok, %{status_code: 401}} -> {:error, :unauthorized}
      {:error, err} -> {:error, err}
      _ -> {:error, :heartbeat_failed}
    end
  end

  defp recalculate_allowed_ips(_state) do
    devices = Devices.fetch_devices()

    ips =
      Enum.flat_map(devices, fn d ->
        tags = DeviceTags.get_tags(d.mac)

        if Enum.any?(tags, &String.starts_with?(&1, "wg")) do
          [d.ip <> "/32"]
        else
          []
        end
      end)
      |> Enum.sort()
      |> Enum.uniq()

    ips
  end

  defp maybe_reregister(state, new_allowed_ips) do
    current = state.allowed_ips -- [state.mesh_ip <> "/32"]

    geo =
      case Tunneld.Geolocation.get_location() do
        {:ok, loc} -> Map.take(loc, [:country_code, :country_name, :latitude, :longitude])
        _ -> %{}
      end

    geo_changed = geo != Map.get(state, :last_geo, %{})

    if new_allowed_ips != current or geo_changed do
      pubkey = Wireguard.get_public_key()

      case register_with_relay(state, pubkey, state.node_name, new_allowed_ips) do
        {:ok, _} ->
          all = [state.mesh_ip <> "/32" | new_allowed_ips]
          %{state | allowed_ips: all, last_geo: geo}

        {:error, reason} ->
          Logger.warning("Mesh re-registration failed: #{inspect(reason)}")
          state
      end
    else
      state
    end
  end

  defp fetch_peers(state) do
    url = "#{state.coordinator_url}/peers"

    case HTTPoison.get(url, headers(state, state.node_id)) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, list} when is_list(list) ->
            peers = Map.new(list, fn p -> {p["pubkey"], p} end)
            {:ok, peers}

          _ ->
            {:error, :invalid_peers}
        end

      {:ok, %{status_code: 401}} ->
        {:error, :unauthorized}

      {:error, err} ->
        {:error, err}

      _ ->
        {:error, :fetch_peers_failed}
    end
  end

  defp update_mesh_peers(state, peers) do
    peer_allowed =
      peers
      |> Map.values()
      |> Enum.flat_map(fn p -> [p["mesh_ip"] <> "/32" | p["allowed_ips"] || []] end)
      |> Enum.uniq()

    all_allowed = ["10.200.0.0/16" | peer_allowed]

    pubkey = state.relay_pubkey

    if pubkey do
      Logger.info("Updating relay peer allowed-ips: #{Enum.join(all_allowed, ",")}")
      Wireguard.add_mesh_peer(pubkey, state.relay_endpoint, all_allowed)
    end

    %{state | peers: peers}
  end

  defp register_with_relay(state, pubkey, name, allowed_ips) do
    url = "#{state.coordinator_url}/register"

    geo_data =
      case Tunneld.Geolocation.get_location() do
        {:ok, loc} ->
          %{
            public_ip: loc[:ip],
            country_code: loc[:country_code],
            country_name: loc[:country_name],
            latitude: loc[:latitude],
            longitude: loc[:longitude]
          }

        _ ->
          %{}
      end

    payload = %{
      node_id: state.node_id,
      pubkey: pubkey,
      name: name,
      allowed_ips: allowed_ips
    }
    |> Map.merge(geo_data)

    case HTTPoison.post(url, Jason.encode!(payload), headers(state)) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"mesh_ip" => mesh_ip}} -> {:ok, mesh_ip}
          _ -> {:error, :invalid_register_response}
        end

      {:ok, %{status_code: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status_code: 400}} ->
        {:error, :bad_request}

      {:error, err} ->
        {:error, err}

      _ ->
        {:error, :register_failed}
    end
  end

  defp fetch_hub(state) do
    url = "#{state.coordinator_url}/hub"

    case HTTPoison.get(url, headers(state, state.node_id)) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, hub} -> {:ok, hub}
          _ -> {:error, :invalid_hub_response}
        end

      {:ok, %{status_code: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:error, err} ->
        {:error, err}

      _ ->
        {:error, :fetch_hub_failed}
    end
  end

  defp configure_relay_peer(hub) do
    pubkey = hub["relay_pubkey"]
    endpoint = hub["relay_endpoint"]
    Wireguard.add_mesh_peer(pubkey, endpoint, ["10.200.0.0/16"])
  end

  defp headers(state, node_id \\ nil) do
    base = [
      {"Authorization", "Bearer #{state.token}"},
      {"Content-Type", "application/json"}
    ]

    if node_id do
      [{"X-Node-ID", node_id} | base]
    else
      base
    end
  end

  defp load_persisted_config do
    path = Path.join(Tunneld.Config.fs_root(), "mesh_config.json")

    case Tunneld.Persistence.read_json(path) do
      {:ok, %{} = data} ->
        base = Application.get_env(:tunneld, :mesh, [])

        [
          coordinator_url: data["coordinator_url"] || Keyword.get(base, :coordinator_url),
          token: data["token"] || Keyword.get(base, :token),
          node_name: data["node_name"] || Keyword.get(base, :node_name, ""),
          enabled: Map.get(data, "enabled", Keyword.get(base, :enabled, false)),
          poll_interval: Keyword.get(base, :poll_interval, 25_000),
          wg_mtu: Map.get(data, "wg_mtu", 1280)
        ]

      _ ->
        Application.get_env(:tunneld, :mesh, [])
    end
  end

  defp load_or_create_node_id do
    path = Path.join(Tunneld.Config.fs_root(), "mesh_node_id.json")

    case Tunneld.Persistence.read_json(path) do
      {:ok, %{"node_id" => id}} -> id
      _ ->
        id = UUID.uuid4()
        Tunneld.Persistence.write_json(path, %{"node_id" => id})
        id
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)

  defp broadcast(state) do
    safe = Map.drop(state, [:token])

    if Process.whereis(@pubsub) != nil do
      Phoenix.PubSub.broadcast(@pubsub, @topic, %{
        id: "mesh_server",
        module: TunneldWeb.Live.Components.Mesh.Server,
        data: safe
      })
    end
  end
end

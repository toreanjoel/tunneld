defmodule Tunneld.Servers.Devices do
  @moduledoc """
  Polls the dnsmasq DHCP lease file to track devices connected to the Tunneld network.

  Every `@interval` milliseconds, reads `/var/lib/misc/dnsmasq.leases` (or mock data),
  parses each lease line into a device map (MAC, IP, hostname, expiry), probes each
  device for reachability, and broadcasts the device list to the dashboard via PubSub.

  The last result is kept in state so `current/0` answers immediately - the UI
  paints from that cache on open and calls `sync_now/0` for a fresh read, rather
  than showing "scanning" until the next tick.

  Also supports revoking a device's DHCP lease by MAC address, which removes the
  lease line and restarts dnsmasq to force the device off the network.
  """
  use GenServer
  require Logger

  @interval 10_000
  @probe_ttl_s 30
  @path "/var/lib/misc/dnsmasq.leases"
  @notifications_topic "notifications"
  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    send(self(), :sync)
    {:ok, %{probes: %{}}}
  end

  @doc """
  Return the current devices from the GenServer state.
  If no data yet, returns an empty map.
  """
  def current do
    try do
      GenServer.call(__MODULE__, :current)
    catch
      :exit, _ -> %{count: 0, devices: [], loaded: false}
    end
  end

  @doc """
  Force an immediate sync: fetch devices and broadcast now.

  Called whenever the operator opens the devices panel or changes something on
  a device, so the UI never has to wait out the poll interval.
  """
  def sync_now do
    GenServer.cast(__MODULE__, :sync_now)
  catch
    :exit, _ -> :ok
  end

  def handle_call(:current, _from, state) do
    result = %{
      count: Map.get(state, :count, 0),
      devices: Map.get(state, :devices, []),
      loaded: Map.get(state, :loaded, false)
    }

    {:reply, result, state}
  end

  def handle_cast(:sync_now, state) do
    {:noreply, sync_and_broadcast(state)}
  end

  def handle_info(:sync, state) do
    state = sync_and_broadcast(state)
    sync_devices()
    {:noreply, state}
  end

  # One place that reads the leases, refreshes reachability, broadcasts, and
  # keeps the result in state. `current/0` therefore always answers from a warm
  # cache, which is what lets the UI paint on open instead of "scanning".
  defp sync_and_broadcast(state) do
    {devices, probes} = annotate_online(fetch_devices(), Map.get(state, :probes, %{}))

    result = %{count: length(devices), devices: devices, loaded: true}

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:devices", %{
      id: "devices",
      module: TunneldWeb.Live.Components.Devices,
      data: result
    })

    state |> Map.merge(result) |> Map.put(:probes, probes)
  end

  # Reachability used to be pinged from the LiveView, inside the component's
  # update/2 - one blocking `ping` per device, on the render path, every time
  # the panel was touched. That is the "it takes a while" in the devices list.
  # Probe here instead, concurrently, and ship the answer with the broadcast.
  defp annotate_online(devices, probes) do
    now = System.monotonic_time(:second)

    stale =
      Enum.reject(devices, fn d ->
        match?(%{at: at} when now - at < @probe_ttl_s, Map.get(probes, d.mac))
      end)

    probed =
      stale
      |> Task.async_stream(fn d -> {d.mac, probe_online(d.ip)} end,
        max_concurrency: 16,
        timeout: 3_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(stale)
      |> Enum.map(fn
        {{:ok, {mac, online}}, _d} -> {mac, online}
        {_, d} -> {d.mac, false}
      end)
      |> Map.new()

    probes =
      Enum.reduce(probed, probes, fn {mac, online}, acc ->
        Map.put(acc, mac, %{at: now, online: online})
      end)

    # Drop probe entries for devices that no longer hold a lease.
    macs = MapSet.new(devices, & &1.mac)
    probes = Map.filter(probes, fn {mac, _} -> MapSet.member?(macs, mac) end)

    devices =
      Enum.map(devices, fn d ->
        Map.put(d, :online, get_in(probes, [d.mac, :online]) || false)
      end)

    {devices, probes}
  end

  defp probe_online(ip) do
    if mock?() do
      true
    else
      case System.cmd("ping", ["-c", "1", "-W", "1", ip], stderr_to_stdout: true) do
        {_, 0} -> true
        _ -> false
      end
    end
  rescue
    _ -> false
  end

  defp sync_devices() do
    :timer.send_after(@interval, :sync)
  end

  defp delete_lease_line(_mac, true), do: {:ok, :mock}

  defp delete_lease_line(mac, false) do
    case File.read(@path) do
      {:ok, content} ->
        filtered =
          content
          |> String.split("\n")
          |> Enum.reject(&String.contains?(&1, mac))
          |> Enum.join("\n")

        case File.write(@path, filtered) do
          :ok -> {:ok, :deleted}
          {:error, reason} -> {:error, {:write_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:read_failed, reason}}
    end
  end

  defp restart_dnsmasq(true), do: :ok

  defp restart_dnsmasq(false) do
    try do
      Tunneld.Servers.Services.restart_service(:dnsmasq, :no_notify)
      :ok
    rescue
      e -> {:error, {:restart_failed, e}}
    catch
      kind, err -> {:error, {:restart_failed, {kind, err}}}
    end
  end

  @doc """
  Read current devices from dnsmasq.leases (or mock), format them,
  and return %{count, devices}
  """
  def fetch_devices() do
    {data, _} =
      if mock?() do
        Tunneld.Servers.FakeData.devices()
      else
        case File.read(@path) do
          {:ok, content} -> {content, 0}
          {:error, _} -> {"", 1}
        end
      end

    clean_data = String.trim(data)

    leases =
      if clean_data == "", do: [], else: String.split(clean_data, "\n")

    Enum.map(leases, fn lease ->
      [lease_expiry, mac, ip, hostname, client_id] = String.split(lease, " ")

      %{
        expiry: lease_expiry,
        mac: mac,
        ip: ip,
        hostname: hostname,
        client_id: client_id,
        type: ""
      }
    end)
  end

  @doc """
  Revoke a device's lease by MAC address.

  Validates the MAC format before passing it to any system command to
  prevent command injection via the `sed` call.
  """
  def revoke_lease(mac) when is_binary(mac) do
    unless valid_mac?(mac) do
      Phoenix.PubSub.broadcast(Tunneld.PubSub, @notifications_topic, %{
        type: :error,
        message: "Invalid MAC address format: #{mac}"
      })

      {:error, :invalid_mac}
    else
      do_revoke_lease(mac)
    end
  end

  defp valid_mac?(mac) do
    Regex.match?(~r/^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$/, mac)
  end

  defp do_revoke_lease(mac) do
    with {:ok, _} <- delete_lease_line(mac, mock?()),
         :ok <- restart_dnsmasq(mock?()) do
      Phoenix.PubSub.broadcast(Tunneld.PubSub, @notifications_topic, %{
        type: :info,
        message: "Lease for #{mac} revoked. Device will drop off shortly once sync updates."
      })

      :ok
    else
      {:error, reason} ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, @notifications_topic, %{
          type: :error,
          message: "Failed to revoke lease for #{mac}: #{inspect(reason)}"
        })

        {:error, reason}
    end
  end
end

defmodule Tunneld.Servers.Devices do
  @moduledoc """
  Polls the dnsmasq DHCP lease file to track devices connected to the Tunneld network.

  Every `@interval` milliseconds, reads `/var/lib/misc/dnsmasq.leases` (or mock data),
  parses each lease line into a device map (MAC, IP, hostname, expiry), and broadcasts
  the device list to the dashboard via PubSub.

  Also supports revoking a device's DHCP lease by MAC address, which removes the
  lease line and restarts dnsmasq to force the device off the network.
  """
  use GenServer
  require Logger

  @interval 10_000
  @path "/var/lib/misc/dnsmasq.leases"
  @notifications_topic "notifications"
  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init devices
  """
  def init(_) do
    send(self(), :sync)
    {:ok, %{}}
  end

  # periodic sync/broadcast
  def handle_info(:sync, state) do
    devices = fetch_devices()

    result = %{
      count: length(devices),
      devices: devices
    }

    # Broadcast to the live view (or parent) so it can update the Devices component.
    # Use an id that matches the one used in your live_component render.
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:devices", %{
      # Make sure this matches your component's id.
      id: "devices",
      module: TunneldWeb.Live.Components.Devices,
      data: result
    })

    sync_devices()
    {:noreply, Map.merge(state, result)}
  end

  # schedule next sync
  defp sync_devices() do
    :timer.send_after(@interval, :sync)
  end

  # remove the matching MAC line from the leases file
  # mock mode: just pretend success
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

  # restart dnsmasq using our Services server
  # mock mode: pretend success
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
        Tunneld.Servers.FakeData.Devices.get_data()
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

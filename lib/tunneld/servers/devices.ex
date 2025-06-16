defmodule Tunneld.Servers.Devices do
  @moduledoc """
  Manage devices connected to the network
  """
  use GenServer
  require Logger

  @interval 10_000
  @path "/var/lib/misc/dnsmasq.leases"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init devices
  """
  def init(_) do
    # We start the process locally on the host to make terminal accessible
    if not Application.get_env(:tunneld, :mock_data, false) do
      Task.start(fn ->
        System.cmd(
          "ttyd",
          [
            "-W",
            "-p",
            Application.get_env(:tunneld, :ttyd)[:port],
            "bash"
          ],
          stderr_to_stdout: true
        )
      end)
    end

    # Start the sync to listen for device connection changes
    send(self(), :sync)
    {:ok, %{}}
  end

  # Get the current devices connected to the network
  def handle_call(:init_state, _from, state) do
    leases = fetch_devices()
    state = Map.put(state, :leases, leases)
    {:reply, {:ok, leases}, state}
  end

  # Get the data and restart sync
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

  # The job that will start interval sync
  defp sync_devices() do
    :timer.send_after(@interval, :sync)
  end

  def fetch_devices() do
    {data, _} =
      if Application.get_env(:tunneld, :mock_data, false) do
        Tunneld.Servers.FakeData.Devices.get_data()
      else
        System.cmd("cat", [@path])
      end

    clean_data = String.trim(data)

    leases =
      if clean_data == "",
        do: [],
        else: String.split(clean_data, "\n")

    # Read whitelist policies
    whitelist =
      case Tunneld.Servers.Whitelist.read_file() do
        {:ok, policies} -> policies
        _ -> []
      end

    Enum.map(leases, fn lease ->
      [lease_expiry, mac, ip, hostname, client_id] = String.split(lease, " ")
      access = Enum.any?(whitelist, fn policy -> policy["mac"] == mac end)

      %{
        expiry: lease_expiry,
        mac: mac,
        ip: ip,
        hostname: hostname,
        client_id: client_id,
        # You can later determine type dynamically if needed.
        type: "",
        # This will be true if the device is in the whitelist.
        access: access
      }
    end)
  end

  def init_state(), do: GenServer.call(__MODULE__, :init_state)
end

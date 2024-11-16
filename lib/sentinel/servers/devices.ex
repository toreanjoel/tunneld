defmodule Sentinel.Servers.Devices do
  @moduledoc """
  Manage devices connected to the network
  """
  use GenServer
  require Logger

  @interval 10_000
  @topic "sentinel:devices"

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

  @doc """
  Get all of the information from the devices and leases
  Note: for now the user needs to get everything
  """
  def handle_call(:get_state, _from, state) do
    # TODO: Get the devices
    {:reply, {:ok, state}, state}
  end

  # we get the current devices connected to the network
  def handle_call(:get_devices, _from, state) do
    leases = fetch_devices()
    state = Map.put(state, :leases, leases)
    {:reply, {:ok, leases}, state}
  end

  # get the data and restart sync
  def handle_info(:sync, state) do
    # TODO: Here we get the logs and also any specific information we want to broadcast i.e count of devices
    devices = fetch_devices()
    result = %{
      count: devices |> length(),
      devices: devices
    }

    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:device_info, result})

    # Refetch
    sync_devices()

    {:noreply, Map.merge(state, result)}
  end

  # The job that will start interval sync
  defp sync_devices() do
    :timer.send_after(@interval, :sync)
  end

  # get the current devices connected to the network
  def fetch_devices() do
    {data, _} = System.cmd("bash", ["./sh/leases.sh"])
    clean_data = data |> String.trim

    leases =
      if clean_data == "",
        do: [],
        else: clean_data |> String.split("\n")

    Enum.map(leases, fn lease ->
      [lease_expiry, mac_addr, ip, host_name, client_id] = String.split(lease, " ")

      %{
        expiry: lease_expiry,
        mac_addr: mac_addr,
        ip: ip,
        host_name: host_name,
        client_id: client_id
      }
    end)
  end

  # Get entire state details for the devices
  def get_state(), do: GenServer.call(__MODULE__, :get_state)
  def get_devices(), do: GenServer.call(__MODULE__, :get_devices)
end

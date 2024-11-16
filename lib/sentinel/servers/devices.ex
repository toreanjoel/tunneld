defmodule Sentinel.Servers.Devices do
  @moduledoc """
  Manage devices connected to the network
  """
  use GenServer
  require Logger

  @interval 30_000
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

  # get the data and restart sync
  def handle_info(:sync, state) do
    # TODO: Here we get the logs and also any specific information we want to broadcast i.e count of devices
    result = %{ count: Enum.random(1..30_000)}

    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:device_info, result})

    # Refetch
    sync_devices()

    {:noreply, Map.merge(state, result)}
  end

  # The job that will start interval sync
  defp sync_devices() do
    :timer.send_after(@interval, :sync)
  end

  # Get entire state details for the devices
  def get_state(), do: GenServer.call(__MODULE__, :get_state)
end

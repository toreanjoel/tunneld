defmodule Sentinel.Servers.Blacklist do
  @moduledoc """
  Manage blacklist domains
  """
  use GenServer
  require Logger

  @interval 30_000
  @topic "sentinel:blacklist"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init blacklist
  """
  def init(_) do
    send(self(), :sync)
    {:ok, %{}}
  end

  @doc """
  Get all of the information around blacklist
  Note: for now the user needs to get everything
  """
  def handle_call(:get_state, _from, state) do
    # TODO: Get the blacklist
    {:reply, {:ok, state}, state}
  end

  # get the data and restart sync
  def handle_info(:sync, state) do
    # TODO: Here we get the logs and also any specific information we want to broadcast i.e count of blacklist
    result = %{ count: Enum.random(1..30_000)}

    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:blacklist_info, result})

    # Refetch
    sync_blacklist()

    {:noreply, Map.merge(state, result)}
  end

  # The job that will start interval sync
  defp sync_blacklist() do
    :timer.send_after(@interval, :sync)
  end

  # Get entire state details for the blacklist
  def get_state(), do: GenServer.call(__MODULE__, :get_state)
end

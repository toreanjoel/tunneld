defmodule Sentinel.Servers.Logs do
  @moduledoc """
  The log server managing logs of requests done through the system
  """
  use GenServer
  require Logger

  @interval 30_000
  @topic "sentinel:logs"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init Logs
  """
  def init(_) do
    send(self(), :sync)
    {:ok, %{}}
  end

  @doc """
  Get all of the log information from the log file
  Note: for now the user needs to get everything
  """
  def handle_call(:get_state, _from, state) do
    # TODO: Get the logs
    {:reply, {:ok, state}, state}
  end

  # get the data and restart sync
  def handle_info(:sync, state) do
    # TODO: Here we get the logs and also any specific information we want to broadcast i.e count of logs
    result = %{ count: Enum.random(1..30_000)}

    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:log_info, result})

    # Refetch
    sync_logs()

    {:noreply, Map.merge(state, result)}
  end

  # The job that will start interval sync
  defp sync_logs() do
    :timer.send_after(@interval, :sync)
  end

  # Get entire state details for the logs
  def get_state(), do: GenServer.call(__MODULE__, :get_state)
end

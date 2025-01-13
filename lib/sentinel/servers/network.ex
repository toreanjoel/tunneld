defmodule Sentinel.Servers.Network do
  @moduledoc """
  The network server used to get the network details
  """
  use GenServer
  require Logger

  @interval 1_200_000
  @topic "sentinel:network"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init internet speed details
  Note: we could make a struct here that maps to the tpe for the network
  """
  def init(_) do
    sync_network()
    {:ok, %{}}
  end

  @doc """
  Get the entire state details for the latency and speed of the network
  Note: for now the user needs to get everything
  """
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # get the data and restart sync
  def handle_info(:sync, state) do
    result = try do
      # {data, _exit_code} = System.cmd("speedtest", ["--accept-license", "--format=json"])

      # result =
      #   data
      #   |> String.trim()
      #   |> Jason.decode!()

      # # Broadcast the result to the topic
      # Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:network_info, result})

      # # Refetch
      # sync_network()

      # result
      %{}
    rescue
      _ ->
        # fallback for when the command fails
        %{}
      end

    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:network_info, result})
    {:noreply, Map.merge(state, result)}
  end

  # The job that will start interval sync
  defp sync_network() do
    :timer.send_after(@interval, :sync)
  end

  # Get details around the network - added longer timeout incase we have to for speedtest lib
  def get_state(), do: GenServer.call(__MODULE__, :get_state, 30_000)
end

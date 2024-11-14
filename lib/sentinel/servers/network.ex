defmodule Sentinel.Servers.Network do
  @moduledoc """
  The network server used to get the network details
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # The host server we check against - Google DNS
  @host "8.8.8.8"

  @doc """
  Init internet speed details
  """
  def init(_) do
    # Base state
    state = sync_network()
    {:ok, state}
  end

  @doc """
  Get the entire state details for the latency and speed of the network
  """
  def handle_call(:get_all, _from, _state) do
    state = sync_network()
    {:reply, {:ok, state}, state}
  end

  # Get the latency
  def handle_call(:get_latency, _from, _state) do
    state = sync_network()
    {:reply, {:ok, state.latency}, state}
  end

  # Get the speed
  def handle_call(:get_speed, _from, _state) do
    state = sync_network()
    {:reply, {:ok, state.speed}, state}
  end

  # sync the network details from the currrent device
  defp sync_network() do
    {output, 0} = System.cmd("ping", ["-c", "1", @host])

    # We get the latency - try catch for cases there are errors
    latency = try do
      output
        |> String.split(" ")
        |> Enum.at(11)
        |> String.slice(5..-1//1)
        |> String.to_float()
    catch
      _ -> 0
    end

    %{
      latency: latency,
      speed: 0
    }
  end

  # Get details around the network
  def get_all(), do: GenServer.call(__MODULE__, :get_all)
  def get_latency(), do: GenServer.call(__MODULE__, :get_latency)
  def get_speed(), do: GenServer.call(__MODULE__, :get_speed)
end

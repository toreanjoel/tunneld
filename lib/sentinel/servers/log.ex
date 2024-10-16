defmodule Sentinel.Servers.Log do
  @moduledoc """
  Log server that logs requests
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init the GenServer with an empty state.
  """
  def init(_) do
    {:ok, %{}}
  end

  # Cast reqeuests to add to the log - persist to file
end

defmodule Sentinel.Servers.Broadcast do
  @moduledoc """
  Handle broadcasting to channels
  """
  use GenServer
  require Logger

  # info channel topics
  @info %{
    :system => "sentinel:info"
  }

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init state
  """
  def init(_) do
    {:ok, :no_state}
  end

  @doc """
  Send a message to topics
  """
  def handle_cast({type, msg}, state) do
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @info.system, {type, msg})
    {:noreply, state}
  end

  @doc """
  Send a message to topics - make sure to send a type as an event aling with the message
  """
  def info(type, str), do: GenServer.cast(__MODULE__, {type, str})

end

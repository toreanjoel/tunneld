defmodule Sentinel.Servers.Broadcast.System do
  @moduledoc """
  Handle broadcasting to channels for internal system messages to client
  """
  use GenServer
  require Logger

  # info channel topics
  @topic %{
    :info => "sentinel:info"
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
  def handle_cast(msg, state) do
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic.info, {:info, msg})
    {:noreply, state}
  end

  @doc """
  Send a message to topics - make sure to send a type as an event aling with the message
  """
  def emit(msg), do: GenServer.cast(__MODULE__, msg)

  @doc """
  Get the channel topic name - system info
  """
  def topic(:info), do: @topic.info

end

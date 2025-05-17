defmodule Sentinel.Servers.Sockets.SentinetClient do
  @moduledoc """
  This is the client that will be started the current machine used in order to make instances or connections.
  We will use this module to connect to phoenix channels and handle responses

  NOTE: This needs to be added dynamically on startup if we plan to connect to multiple servers
  """
  use Slipstream
  require Logger

  @topic "sentinet"
  @default_connect_timeout 30_000

  def start_link(config) do
    # This is so we can pass a unique name when we dynamically start this
    # Keep in mind the conenct / disconnect / event will need to reference the name
    name = Keyword.get(config, :name, __MODULE__)
    Slipstream.start_link(__MODULE__, config, name: name)
  end

  @impl Slipstream
  def init(config) do
    # In a real scenario, you would fetch the URL and metadata from a file or configuration here
    url = Application.fetch_env!(:sentinel, :slipstream_url)
    metadata = Application.fetch_env(:sentinel, :slipstream_metadata) || %{}

    state = %{
      retry_attempts: 0,
      url: url,
      metadata: metadata
    }

    {:ok, state}
  end

  @doc """
  Handle the connect request from the client
  """
  @impl Slipstream
  def handle_call(:connect, _from, socket) do
    new_socket =
      socket
      |> assign(:uri, socket.state.url)
      |> assign(:metadata, socket.state.metadata)

    case connect(new_socket) |> await_connect(@default_connect_timeout) do
      {:ok, s} -> {:reply, :connected, s}
      {:error, reason} -> {:reply, {:error, reason}, new_socket}
    end
  end

  @doc """
  handle a cast when we send an event to the server
  """
  @impl Slipstream
  def handle_cast({:event, payload}, socket) do
    # here we send a message to the server
    push(socket, @topic, "event", {:event, payload})
    {:noreply, socket}
  end

  @doc """
  Handle the disconnect request from the client
  """
  @impl Slipstream
  def handle_call(:disconnect, _from, socket) do
    # Here we disconnect on behalf of the client
    await_leave!(socket, @topic, @default_connect_timeout)
    await_disconnect!(socket, @default_connect_timeout)

    {:reply, :disconnected, socket}
  end

  @doc """
  Hanle the initial connection after the socket connects
  """
  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("Connected to remote socket at: #{socket.assigns.uri}")

    {:ok,
     socket
     |> assign(:retry_attempts, 0)
     |> join(@topic, socket.assigns.metadata || %{})}
  end

  @doc """
  When this client does a push, this is if that message was replied to, we catch those replies
  This is not needed but incase we need to handle custom events from the server responses to push() events.
  """
  @impl Slipstream
  def handle_reply(ref, reply, %{assigns: %{request: _}} = socket) do
    IO.inspect(reply, label: "reply to my request")
    {:ok, socket}
  end

  @doc """
  Handle when there is a disconnect message from the server, try to reconnect
  """
  @impl Slipstream
  def handle_disconnect(reason, socket) do
    Logger.warn("Socket disconnected due to: #{inspect(reason)}, attempting to reconnect.")

    case reconnect(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end
  end

  @doc """
  A message from the server, based on async events from the client
  We dont need to reply to the messages coming in here
  """
  @impl Slipstream
  def handle_info({:slipstream_message, _channel, event, payload}, socket) do
    if event == "event" do
      # Handle the incoming event payload
      IO.inspect({:received_event, payload}, label: "Server Event")
    end
    {:noreply, socket}
  end

  @doc """
  Handle when the user left intentionally
  """
  @impl Slipstream
  def handle_topic_close(topic, :left, socket) do
    Logger.info("Left topic: #{topic}")
    {:stop, :normal, socket}
  end

  @doc """
  There was a close for some reason, disconnect etc? we do a retry
  """
  @impl Slipstream
  def handle_topic_close(topic, reason, socket) do
    Logger.warn("Topic #{topic} closed due to: #{reason}. Attempting to rejoin.")
    attempt = socket.assigns.retry_attempts

    if attempt < 10 do
      socket =
        socket
        |> assign(:retry_attempts, attempt + 1)

      rejoin(socket, topic)
    else
      Logger.error("Failed to rejoin topic #{topic} after #{attempt} attempts. Disconnecting.")
      {:stop, :disconnected, socket}
    end
  end

  @doc """
  Disconnect from the node and leave the channels
  """
  def node_disconnect(name \\ __MODULE__) do
    GenServer.call(name, :disconnect, @default_connect_timeout)
  end

  @doc """
  Connect to the a server and have it attempt to join the channel of that server
  """
  def node_connect(name \\ __MODULE__) do
    GenServer.call(name, :connect, @default_connect_timeout)
  end

  @doc """
  Send an event or message to  a server
  """
  def node_event(name \\ __MODULE__, payload) do
    GenServer.cast(name, {:event, payload})
  end

  @doc """
  Hanel when there is some error with this processes
  """
  @impl Slipstream
  def terminate(reason, socket) do
    Logger.error("Terminated with reason: #{inspect(reason)}")
    {:stop, :normal, socket}
  end
end

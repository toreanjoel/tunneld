defmodule Sentinel.Servers.SocketClient do
  @moduledoc """
  Client to connect with channels to the a phoenix socket

  # Start the client with the desired WebSocket URI
  {:ok, _pid} = Sentinel.Servers.SocketClient.start_link(uri: "ws://localhost/socket/websocket")

  # Send an event to the channel
  Sentinel.Servers.SocketClient.send_event(%{message: "Hello, Phoenix!"})

  # Disconnect from the channel
  Sentinel.Servers.SocketClient.disconnect()

  """
  alias Sentinel.Encryption
  use Slipstream
  require Logger

  @topic "sentinet"

  @doc """
  Starts the Slipstream client process.
  """
  def start_link(config) do
    Slipstream.start_link(__MODULE__, config, name: __MODULE__)
  end

  @spec init(keyword()) :: {:ok, Slipstream.Socket.t(), {:continue, :init_state}}
  @doc """
  init with base config for the urls or server details that we will be trying to conenct to
  """
  @impl Slipstream
  def init(config) do
    socket = connect!(config)
    {:ok, socket, {:continue, :init_state}}
  end

  @doc """
  The side effect happening after connecting to setup the base init data to join with
  """
  @impl Slipstream
  def handle_continue(:init_state, socket) do
    # TODO: We need to encrypt the encrypted token and socket client needs to decrpt to check it matches
    socket =
      socket
      |> assign(:retry_attempts, 0)
      |> assign(:metadata, %{token: Sentinel.Servers.Encryption.fetch_settings()})

    {:noreply, socket}
  end

  @doc """
  Callback after connecting to try and join to a server
  """
  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("Joining topic #{@topic}")
    {:ok, join(socket, @topic, socket.assigns.metadata)}
  end

  @doc """
  Send a request to the server with a given payload
  """
  @impl Slipstream
  def handle_cast({:event, payload}, socket) do
    Logger.debug("Pushing event to #{@topic}: #{inspect(payload)}")
    push(socket, @topic, "event", payload)
    {:noreply, socket}
  end

  @doc """
  Server request to disconnect from the given server
  """
  @impl Slipstream
  def handle_cast(:disconnect, socket) do
    Logger.info("Manually disconnecting from #{@topic}")

    socket =
      socket
      |> disconnect()
      |> await_disconnect()

    {:noreply, socket}
  end

  @doc """
  When we get a reply back to us on the topic
  """
  @impl Slipstream
  def handle_reply(_ref, reply, socket) do
    # TODO: We need to decode and decrypt the response data
    Logger.debug("Reply received: #{inspect(reply)}")
    {:ok, socket}
  end

  @doc """
  Handle the disconnects if they are intentional or not and try get the system reconnected
  """
  @impl Slipstream
  def handle_disconnect(:client_disconnect_requested, socket) do
    Logger.warn("Disconnecting client as per their request")
    {:stop, :disconnected, socket}
  end

  def handle_disconnect(reason, socket) do
    Logger.warn("Disconnected: #{inspect(reason)}. Attempting to reconnect.")

    case reconnect(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end
  end

  @doc """
  We listen on the join result if there is a issue we retry a few times if needed
  """
  @impl Slipstream
  def handle_topic_close(topic, _reason, socket) do
    attempt = socket.assigns[:retry_attempts] || 0

    if attempt < 5 do
      Logger.warn("Join refused for #{topic}, retrying (attempt #{attempt + 1})")

      socket = assign(socket, :retry_attempts, attempt + 1)

      case rejoin(socket, topic) do
        {:ok, updated_socket} ->
          {:ok, updated_socket}

        {:error, reason} ->
          Logger.error("Rejoin failed: #{inspect(reason)}")
          {:stop, reason, socket}
      end
    else
      Logger.error("Join refused for #{topic} too many times. Giving up.")
      {:stop, :normal, socket}
    end
  end

  @doc """
  When the process exits, we need to handle and log only for now but this is when we kill this process
  """
  @impl true
  def terminate(reason, _socket) do
    Logger.warn("Client shutting down with reason: #{inspect(reason)}")
    :ok
  end

  @doc """
  Disconnects the client from the Phoenix channel.
  """
  def disconnect, do: GenServer.cast(__MODULE__, :disconnect)

  @doc """
  Sends an event payload to the Phoenix channel.
  """
  def send_event(payload), do: GenServer.cast(__MODULE__, {:event, payload})
end

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
  use Slipstream
  require Logger

  @topic "sentinet:host"

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
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
    # Make a request to auth the device on the channel
    device_id = UUID.uuid4()

    socket =
      socket
      |> assign(:retry_attempts, 0)
      # TODO: We need to send the data
      |> assign(:metadata, %{
        device: device_id,
        token:
          Sentinel.Encryption.generate_auth_token(
            Sentinel.Servers.Encryption.fetch_settings(),
            device_id
          )
      })

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
    # Encode the json payload so that we can send that encrypted through
    encrypted = Sentinel.Servers.Encryption.encrypt_payload(Jason.encode!(payload))
    encoded = Base.encode64(encrypted)

    push(socket, @topic, "event", encoded)
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


    # this is to stop the current process
    {:stop, :disconnected, socket}
  end

  @doc """
  When we get a reply back to us on the topic
  """
  @impl Slipstream
  def handle_reply(_ref, {_, reply}, socket) do
    resp =
      Base.decode64!(reply) |> Sentinel.Servers.Encryption.decrypt_payload() |> Jason.decode!()

    # Do something by sending it to the client if we need to send messages back
    Logger.debug("Reply received: #{inspect(resp)}")

    # Reset retry attempts
    socket = socket |> assign(:retry_attempts, 0)
    {:ok, socket}
  end

  @doc """
  When a general message comes from the server
  """
  @impl Slipstream
  def handle_message(topic, event, message, socket) do
    IO.inspect("Randome message from the server: #{topic}:#{event}:#{inspect(message)}")
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
  def send_event(%{ "type" => "init", "data" => _} = payload), do: GenServer.cast(__MODULE__, {:event, payload})
  # This is to enfore that we pass the artifact when sending a request to trigger
  def send_event(%{ "type" => "trigger", "data" => %{ "id" => _, "payload" => _}} = payload), do: GenServer.cast(__MODULE__, {:event, payload})
end

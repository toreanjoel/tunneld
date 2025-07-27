defmodule Tunneld.Servers.SocketClient do
  use Slipstream
  require Logger

  @topic "tunneld:host"

  @spec start_link(keyword()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(opts) do
    token = Keyword.get(opts, :token, nil)
    uri = Keyword.fetch!(opts, :uri)

    # Always register name, even if connect fails
    Slipstream.start_link(__MODULE__, [uri: uri, token: token], name: __MODULE__)
  end

  @spec wait_for_connection(timeout()) :: :ok | {:error, term()}
  def wait_for_connection(timeout \\ 5_000) do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :not_running}

      _pid ->
        ref = make_ref()
        GenServer.cast(__MODULE__, {:register_waiter, self(), ref})

        receive do
          {:connection_ready, ^ref} -> :ok
          {:connection_failed, ^ref, reason} -> {:error, reason}
        after
          timeout -> {:error, :timeout}
        end
    end
  end

  @impl Slipstream
  def init(opts) do
    uri = Keyword.fetch!(opts, :uri)
    token = Keyword.get(opts, :token, nil)

    case Slipstream.connect(uri: uri) do
      {:ok, socket} ->
        socket =
          socket
          |> assign(:provided_token, token)
          |> assign(:retry_attempts, 0)
          |> assign(:waiters, [])
          |> assign(:connected, false)

        {:ok, socket, {:continue, :init_state}}

      {:error, reason} ->
        # Still start process but mark failure_reason
        socket =
          Slipstream.Socket.new()
          |> assign(:failure_reason, reason)
          |> assign(:connected, false)

        {:ok, socket}
    end
  end

  @impl Slipstream
  def handle_continue(:init_state, socket) do
    device_id = UUID.uuid4()

    token =
      Tunneld.Encryption.generate_auth_token(
        socket.assigns[:provided_token] || Tunneld.Servers.Encryption.fetch_settings(),
        device_id
      )

    socket = assign(socket, :metadata, %{device: device_id, token: token})

    {:noreply, socket}
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("Connected to socket, joining topic #{@topic}")
    {:ok, join(socket, @topic, socket.assigns.metadata)}
  end

  @impl Slipstream
  def handle_join(@topic, _payload, socket) do
    Logger.info("Successfully joined topic #{@topic}")

    # Mark fully connected
    socket = assign(socket, :connected, true)

    # Notify all waiters
    Enum.each(socket.assigns.waiters, fn {pid, ref} ->
      send(pid, {:connection_ready, ref})
    end)

    {:ok, assign(socket, :waiters, [])}
  end

  @impl Slipstream
  def handle_cast({:register_waiter, pid, ref}, socket) do
    waiters = [{pid, ref} | socket.assigns.waiters]
    {:noreply, assign(socket, :waiters, waiters)}
  end

  # Handle failed joins
  @impl Slipstream
  def handle_topic_close(@topic, reason, socket) do
    Logger.error("Join failed for #{@topic}: #{inspect(reason)}")

    Enum.each(socket.assigns.waiters, fn {pid, ref} ->
      send(pid, {:connection_failed, ref, reason})
    end)

    {:ok,
     socket
     |> assign(:connected, false)
     |> assign(:failure_reason, reason)
     |> assign(:waiters, [])}
  end

  @impl Slipstream
  def handle_disconnect(reason, socket) do
    Logger.warn("Disconnected: #{inspect(reason)}. Attempting to reconnect.")
    socket = assign(socket, :connected, false)

    case reconnect(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end
  end

  # Details
  @spec details() :: :not_running | %{connected: boolean(), metadata: map(), reason: term() | nil}
  def details do
    IO.inspect(Process.whereis(__MODULE__))

    case Process.whereis(__MODULE__) do
      nil ->
        :not_running

      _pid ->
        GenServer.call(__MODULE__, :details)
    end
  end

  @impl Slipstream
  def handle_call(:details, _from, socket) do
    details = %{
      connected: Map.get(socket.assigns, :connected, false),
      metadata: Map.get(socket.assigns, :metadata, %{}),
      reason: Map.get(socket.assigns, :failure_reason, nil)
    }

    {:reply, details, socket}
  end

  def disconnect, do: GenServer.cast(__MODULE__, :disconnect)

  def handle_cast(:disconnect, socket) do
    socket =
      socket
      |> disconnect()
      |> await_disconnect()

    {:stop, :disconnected, socket}
  end
end

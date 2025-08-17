defmodule Tunneld.Servers.SocketClient do
  @moduledoc false
  use Slipstream
  require Logger

  @topic "tunneld:host"

  @spec start_link(keyword()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(opts) do
    token = Keyword.get(opts, :token, nil)
    uri = Keyword.fetch!(opts, :uri)
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
          |> assign(:uri, uri)
          |> assign(:provided_token, token)
          |> assign(:retry_attempts, 0)
          |> assign(:waiters, [])
          |> assign(:connected, false)
          |> assign(:metadata, %{})
          |> assign(:reason, nil)
          |> assign(:failure_reason, nil)
          |> assign(:started_at, DateTime.utc_now())
          |> assign(:connected_at, nil)
          |> assign(:last_disconnect_at, nil)
          |> assign(:manual_disconnect, false)
          |> assign(:pending_replies, %{})

        {:ok, socket, {:continue, :init_state}}

      {:error, reason} ->
        socket =
          Slipstream.Socket.new()
          |> assign(:uri, uri)
          |> assign(:provided_token, token)
          |> assign(:retry_attempts, 0)
          |> assign(:waiters, [])
          |> assign(:connected, false)
          |> assign(:metadata, %{})
          |> assign(:reason, reason)
          |> assign(:failure_reason, reason)
          |> assign(:started_at, DateTime.utc_now())
          |> assign(:connected_at, nil)
          |> assign(:last_disconnect_at, nil)
          |> assign(:manual_disconnect, false)
          |> assign(:pending_replies, %{})

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

    {:noreply, assign(socket, :metadata, %{device: device_id, token: token})}
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("Connected, joining #{@topic}")
    {:ok, join(socket, @topic, socket.assigns.metadata)}
  end

  @impl Slipstream
  def handle_join(@topic, _payload, socket) do
    Logger.info("Joined #{@topic}")

    socket =
      socket
      |> assign(:connected, true)
      |> assign(:reason, nil)
      |> assign(:failure_reason, nil)
      |> assign(:connected_at, DateTime.utc_now())

    Enum.each(socket.assigns.waiters, fn {pid, ref} ->
      send(pid, {:connection_ready, ref})
    end)

    {:ok, assign(socket, :waiters, [])}
  end

  @impl Slipstream
  def handle_topic_close(@topic, reason, socket) do
    Logger.error("Join failed for #{@topic}: #{inspect(reason)}")

    Enum.each(socket.assigns.waiters, fn {pid, ref} ->
      send(pid, {:connection_failed, ref, reason})
    end)

    {:ok,
     socket
     |> assign(:connected, false)
     |> assign(:reason, reason)
     |> assign(:failure_reason, reason)
     |> assign(:waiters, [])}
  end

  @impl Slipstream
  def handle_disconnect(reason, socket) do
    Logger.warn("Disconnected: #{inspect(reason)}")
    manual? = Map.get(socket.assigns, :manual_disconnect, false)

    socket =
      socket
      |> assign(:connected, false)
      |> assign(:reason, reason)
      |> assign(:failure_reason, reason)
      |> assign(:last_disconnect_at, DateTime.utc_now())
      |> assign(:retry_attempts, Map.get(socket.assigns, :retry_attempts, 0) + 1)
      |> assign(:manual_disconnect, false)

    if manual? do
      # Manual: do NOT auto-reconnect; keep process alive
      {:ok, socket}
    else
      case reconnect(socket) do
        {:ok, socket} -> {:ok, socket}
        {:error, r} -> {:stop, r, socket}
      end
    end
  end

  @impl Slipstream
  def handle_cast({:register_waiter, pid, ref}, socket) do
    {:noreply, assign(socket, :waiters, [{pid, ref} | socket.assigns.waiters])}
  end

  @impl Slipstream
  def handle_cast({:event_with_reply, payload, caller, ref}, socket) do
    encrypted = Tunneld.Servers.Encryption.encrypt_payload(Jason.encode!(payload))
    encoded = Base.encode64(encrypted)

    {:ok, slip_ref} = push(socket, @topic, "event", encoded)

    pending =
      socket.assigns.pending_replies
      |> Map.put(slip_ref, {caller, ref})

    {:noreply, assign(socket, :pending_replies, pending)}
  end

  @impl Slipstream
  def handle_cast({:event, payload}, socket) do
    encrypted = Tunneld.Servers.Encryption.encrypt_payload(Jason.encode!(payload))
    encoded = Base.encode64(encrypted)
    push(socket, @topic, "event", encoded)
    {:noreply, socket}
  end

  def disconnect, do: GenServer.cast(__MODULE__, :disconnect)

  @impl Slipstream
  def handle_cast(:disconnect, socket) do
    # Mark as manual so handle_disconnect/2 skips auto-reconnect
    socket = assign(socket, :manual_disconnect, true)

    # Do not pipe tuples into assign/3
    {:ok, s1} = disconnect(socket)
    {:ok, s2} = await_disconnect(s1)

    s2 =
      s2
      |> assign(:connected, false)
      |> assign(:reason, :manual_disconnect)
      |> assign(:last_disconnect_at, DateTime.utc_now())

    # Keep the process alive
    {:noreply, s2}
  end

  @doc """
  Synchronous request over the socket, returns {:ok, term} | {:error, term}.
  """
  @spec request_event(map(), non_neg_integer()) :: {:ok, term()} | {:error, term()}
  def request_event(payload, timeout \\ 60_000) do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :not_running}

      _pid ->
        ref = make_ref()
        GenServer.cast(__MODULE__, {:event_with_reply, payload, self(), ref})

        receive do
          {:event_reply, ^ref, result} -> {:ok, result}
        after
          timeout -> {:error, :timeout}
        end
    end
  end

  @impl Slipstream
  def handle_reply(slip_ref, {_, reply}, socket) do
    decrypted =
      reply
      |> Base.decode64!()
      |> Tunneld.Servers.Encryption.decrypt_payload()
      |> Jason.decode!()

    case Map.pop(socket.assigns.pending_replies, slip_ref) do
      {nil, _pending} ->
        {:ok, socket}

      {{caller, user_ref}, remaining} ->
        send(caller, {:event_reply, user_ref, decrypted})
        {:ok, assign(socket, :pending_replies, remaining)}
      end
  end

  @impl Slipstream
  def handle_call(:details, _from, socket) do
    details = %{
      connected: Map.get(socket.assigns, :connected, false),
      metadata: Map.get(socket.assigns, :metadata, %{}),
      reason: Map.get(socket.assigns, :reason, Map.get(socket.assigns, :failure_reason)),
      uri: Map.get(socket.assigns, :uri),
      retry_attempts: Map.get(socket.assigns, :retry_attempts, 0),
      started_at: Map.get(socket.assigns, :started_at),
      connected_at: Map.get(socket.assigns, :connected_at),
      last_disconnect_at: Map.get(socket.assigns, :last_disconnect_at)
    }

    {:reply, details, socket}
  end

  @doc """
  Fire-and-forget helpers used by callers.
  """
  def send_event(%{"type" => "init", "data" => _} = payload),
    do: GenServer.cast(__MODULE__, {:event, payload})

  def send_event(%{"type" => "trigger", "data" => %{"id" => _, "payload" => _}} = payload),
    do: GenServer.cast(__MODULE__, {:event, payload})

  @doc """
  Public details accessor for external callers (e.g. controllers).
  """
  @spec details() :: :not_running | map()
  def details do
    case Process.whereis(__MODULE__) do
      nil -> :not_running
      _pid -> GenServer.call(__MODULE__, :details)
    end
  end
end

defmodule Tunneld.Servers.Session do
  @moduledoc """
  In-memory, IP-keyed authentication session store.

  Each session is a map entry keyed by the client's IP address with an
  `expires_at` Unix timestamp. Sessions are created on successful login,
  renewed on activity, and automatically evicted when expired.

  A periodic cleanup sweeps stale entries every `@interval` milliseconds
  to prevent unbounded state growth.

  All public functions are synchronous (`GenServer.call`) to guarantee
  the caller receives the latest session state.
  """
  use GenServer
  require Logger

  # Cleanup interval for expired sessions (ms)
  @interval 30_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Create or refresh a session for the given IP. Returns `{:ok, "Session Created"}`.
  """
  @spec create(String.t()) :: {:ok, String.t()}
  def create(id), do: GenServer.call(__MODULE__, {:create, id})

  @doc """
  Retrieve a session by IP. Evicts and returns `{:error, reason}` if expired or missing.
  """
  @spec get(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get(id), do: GenServer.call(__MODULE__, {:get, id})

  @doc """
  Returns `true` if the session exists and has not expired.
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(id) do
    case get(id) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Reset the TTL on an existing session. Returns `:ok` or `{:error, reason}` if missing/expired.
  """
  @spec renew(String.t()) :: :ok | {:error, String.t()}
  def renew(id), do: GenServer.call(__MODULE__, {:renew, id})

  @doc """
  Delete a session by IP. Returns `{:ok, "Session deleted"}` or `{:error, reason}`.
  """
  @spec delete(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def delete(id), do: GenServer.call(__MODULE__, {:delete, id})

  @impl true
  def init(_) do
    schedule_cleanup()
    {:ok, %{}}
  end

  # Create or overwrite a session with fresh TTL
  @impl true
  def handle_call({:create, id}, _from, state) do
    now = unix_now()
    ttl = config(:ttl)
    new_state = Map.put(state, id, %{expires_at: now + ttl})
    {:reply, {:ok, "Session Created"}, new_state}
  end

  # Get a session; enforce expiry immediately
  @impl true
  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state, id) do
      {:ok, %{expires_at: exp} = sess} ->
        now = unix_now()

        if exp > now do
          {:reply, {:ok, sess}, state}
        else
          # evict expired
          {:reply, {:error, "Session expired"}, Map.delete(state, id)}
        end

      :error ->
        {:reply, {:error, "Session not found"}, state}
    end
  end

  # Renew a session's expiry if present and not expired
  @impl true
  def handle_call({:renew, id}, _from, state) do
    case Map.fetch(state, id) do
      {:ok, %{expires_at: exp} = sess} ->
        now = unix_now()

        if exp > now do
          ttl = config(:ttl)
          updated = %{sess | expires_at: now + ttl}
          {:reply, :ok, Map.put(state, id, updated)}
        else
          {:reply, {:error, "Session expired"}, Map.delete(state, id)}
        end

      :error ->
        {:reply, {:error, "Session not found"}, state}
    end
  end

  # Delete one session
  @impl true
  def handle_call({:delete, id}, _from, state) do
    if Map.has_key?(state, id) do
      {:reply, {:ok, "Session deleted"}, Map.delete(state, id)}
    else
      {:reply, {:error, "Session not found"}, state}
    end
  end

  # Periodic cleanup of expired sessions
  @impl true
  def handle_info(:init_cleaner, state) do
    now = unix_now()

    updated_state =
      Enum.reduce(state, %{}, fn {id, %{expires_at: exp} = sess}, acc ->
        if exp > now, do: Map.put(acc, id, sess), else: acc
      end)

    schedule_cleanup()
    {:noreply, updated_state}
  end

  defp schedule_cleanup, do: :timer.send_after(@interval, :init_cleaner)
  defp unix_now, do: DateTime.utc_now() |> DateTime.to_unix()

  # Config helper with a default TTL if not configured
  defp config, do: Application.get_env(:tunneld, :auth) || [ttl: 60 * 30]
  defp config(key), do: Keyword.fetch!(config(), key)
end

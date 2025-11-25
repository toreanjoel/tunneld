defmodule Tunneld.Servers.Session do
  @moduledoc """
  Auth session management (IP-keyed).
  """
  use GenServer
  require Logger

  # Cleanup interval for expired sessions (ms)
  @interval 30_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Create/refresh a session for id (IP). Overwrites or creates with fresh TTL.
  @spec create(String.t()) :: {:ok, String.t()}
  def create(id), do: GenServer.call(__MODULE__, {:create, id})

  # Get a session; will evict & return error if expired/missing.
  @spec get(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get(id), do: GenServer.call(__MODULE__, {:get, id})

  # Convenience: is this session currently valid (exists & not expired)?
  @spec valid?(String.t()) :: boolean()
  def valid?(id) do
    case get(id) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # Renew a valid session's expiry (no-op if missing).
  @spec renew(String.t()) :: :ok | {:error, String.t()}
  def renew(id), do: GenServer.call(__MODULE__, {:renew, id})

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

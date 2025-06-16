defmodule Tunneld.Servers.Session do
  @moduledoc """
  Auth session management
  """
  use GenServer
  require Logger

  # Default TTL for sessions in seconds
  @interval 30_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Initialize the session state and start cleanup interval.
  """
  def init(_) do
    schedule_cleanup()
    {:ok, %{}}
  end

  # Add a new session
  def handle_call({:create, id}, _from, state) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    ttl = config(:ttl)

    new_state = Map.put(state, id, %{expires_at: now + ttl})
    {:reply, {:ok, "Session Created"}, new_state}
  end

  # Get a session
  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state, id) do
      {:ok, session} ->
        session = if is_nil(session), do: {:error, session}, else: {:ok, session}
        {:reply, session, state}
      :error -> {:reply, {:error, "Session not found"}, state}
    end
  end

  # Get all sessions
  def handle_call(:get_all, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # Remove all sessions
  def handle_call(:delete_all, _from, _state) do
    {:reply, {:ok, "Removed All Sessions"}, %{}}
  end

  # Delete a single session by ID
  def handle_call({:delete, id}, _from, state) do
    if Map.has_key?(state, id) do
      new_state = Map.delete(state, id)
      {:reply, {:ok, "Session deleted"}, new_state}
    else
      {:reply, {:error, "Session not found"}, state}
    end
  end

  # Periodically clean up expired sessions
  def handle_info(:init_cleaner, state) do
    current_time = DateTime.utc_now() |> DateTime.to_unix()

    updated_state =
      Enum.reduce(state, %{}, fn {id, session}, acc ->
        if session.expires_at > current_time do
          Map.put(acc, id, session)
        else
          Map.delete(acc, id)
        end
      end)

    schedule_cleanup()
    {:noreply, updated_state}
  end

  # Schedule the next cleanup using :timer.send_after
  defp schedule_cleanup() do
    :timer.send_after(@interval, :init_cleaner)
  end

  # Public API functions
  def create(id), do: GenServer.call(__MODULE__, {:create, id})
  def get(id), do: GenServer.call(__MODULE__, {:get, id})
  def get_all(), do: GenServer.call(__MODULE__, :get_all)
  def delete(id), do: GenServer.call(__MODULE__, {:delete, id})
  def delete_all(), do: GenServer.call(__MODULE__, :delete_all)

  # Config helper with a default TTL if not configured
  defp config(), do: Application.get_env(:tunneld, :auth)
  defp config(key), do: config()[key]
end

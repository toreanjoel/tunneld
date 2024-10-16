defmodule Sentinel.Servers.Cache do
  @moduledoc """
  Caching the DNS responses.
  """
  use GenServer
  require Logger

  # This is the time before we remove it from the cache in ms
  @ttl 900
  @sync_interval 60_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init the GenServer with an empty state.
  """
  # Note: we make the system add from it being on, we dont add things on startup
  def init(_) do
    # Check if we need to remove any of the domains from the cache
    init_ttl_check()

    {:ok, %{}}
  end

  # write domain to cache
  def handle_call({:write, domain, ip}, _, state) do
    state = Map.put(state, domain,%{
        ip: ip,
        ttl: DateTime.utc_now |> DateTime.to_unix() |> Kernel.+(@ttl)
      })
    {:reply, :ok, state}
  end

  # remove domain from cache
  def handle_call({:remove, domain}, _, state) do
    state = Map.delete(state, domain)
    {:reply, :ok, state}
  end

  # get domain from cache
  def handle_call({:get, domain}, _, state) do
    {:reply, {:ok, Map.get(state, domain)}, state}
  end

  # do ttl check
  def handle_info(:ttl_check, state) do
    state = Enum.reduce(state, %{}, fn {domain, %{ttl: ttl}}, acc ->
      # We check if the current time is grater than ttl
      if DateTime.utc_now |> DateTime.to_unix() > ttl do
        # If it is, we remove it from the cache
        Map.delete(acc, domain)
      else
        acc
      end
    end)

    {:noreply, state}
  end

  # helper functions to call the process functions and init the ttl check
  def write(domain, ip), do: GenServer.call(__MODULE__, {:write, domain, ip})
  def remove(domain), do: GenServer.call(__MODULE__, {:remove, domain})
  def get(domain), do: GenServer.call(__MODULE__, {:get, domain})

  # init ttl check
  defp init_ttl_check do
    Process.send_after(self(), :ttl_check, @sync_interval)
  end
end

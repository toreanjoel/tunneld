defmodule Sentinel.Servers.Blacklist do
  @moduledoc """
  This module is responsible for managing the blacklist of domains that are not allowed to be resolved.
  """
  use GenServer
  require Logger

  @sync_interval 60_000
  @file_path "blacklist.json"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Initializes the GenServer with an empty state. Plan to read from file if it exists.
  """
  def init(_) do
    # Start sync process for the blacklist to backup to files
    preload = Sentinel.Servers.File.read(@file_path)
    init_blackilist_sync()

    # init state
    state = Map.merge(%{}, preload)
    {:ok, state}
  end

  @doc """
  Adds a domain to the blacklist. The domain is a string and the IP is an IP address.
  We dont need the IP but this is just so we can blacklist the domain and lookup
  """
  def handle_call({:add, %{ domain: domain, ip: ip}}, _from, state) do
    state = Map.put(state, domain, ip)
    {:reply, :ok, state}
  end


  # Removes a domain from the blacklist.
  def handle_call({:remove, domain}, _from, state) do
    {:reply, :ok, Map.delete(state, domain)}
  end

  # Checks if a domain is blacklisted.
  def handle_call({:get, domain}, _from, state) do
    {:reply, Map.has_key?(state, domain), state}
  end


  # Return the blacklisted domains.
  def handle_call(:get_all, _from, state) do
    {:reply, Map.keys(state), state}
  end

  @doc """
  Clears the blacklist and flushes everything.
  """
  def handle_cast(:clear, _state) do
    state = %{}
    {:noreply, state}
  end

  # do backup sync from state to file
  def handle_info(:backup, state) do
    Sentinel.Servers.File.write(state, @file_path)

    # restart sync process again
    init_blackilist_sync()

    {:noreply, state}
  end

  # Helper functions to call the process functions
  def add(domain, ip), do: GenServer.call(__MODULE__, {:add, %{domain: domain, ip: ip}})
  def remove(domain), do: GenServer.call(__MODULE__, {:remove, domain})
  def get(domain), do: GenServer.call(__MODULE__, {:get, domain})
  def get_all, do: GenServer.call(__MODULE__, :get_all)
  def clear, do: GenServer.cast(__MODULE__, :clear)

  # sync process to backup blacklist to files
  defp init_blackilist_sync do
    Process.send_after(self(), :backup, @sync_interval)
  end
end

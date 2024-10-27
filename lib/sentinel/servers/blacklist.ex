defmodule Sentinel.Servers.Blacklist do
  @moduledoc """
  This module is responsible for managing the blacklist of domains that are not allowed to be resolved.
  """
  use GenServer
  require Logger

  @file_path "PATH_BLACKLIST"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Initializes the GenServer with an empty state. Plan to read from file if it exists.
  """
  def init(_) do
    # This is base state that we use to populate if we need
    {:ok, %{}}
  end

  @doc """
  Adds a domain to the blacklist. The domain is a string and the IP is an IP address.
  We dont need the IP but this is just so we can blacklist the domain and lookup
  """
  def handle_call({:add, %{ domain: domain }}, _from, state) do
    state = Map.put(state, domain)
    {:reply, :ok, state}
  end


  # Removes a domain from the blacklist.
  def handle_call({:remove, domain}, _from, state) do
    {:reply, :ok, Map.delete(state, domain)}
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
    Sentinel.Servers.File.delete(@file_path)
    {:noreply, state}
  end

  # Helper functions to call the process functions
  def add(domain, ip), do: GenServer.call(__MODULE__, {:add, %{domain: domain, ip: ip}})
  def remove(domain), do: GenServer.call(__MODULE__, {:remove, domain})
  def get_all, do: GenServer.call(__MODULE__, :get_all)
  def clear, do: GenServer.cast(__MODULE__, :clear)
end

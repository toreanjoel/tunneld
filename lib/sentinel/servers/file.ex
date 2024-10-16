defmodule Sentinel.Servers.File do
  @moduledoc """
  Write to files and read from files.
  """
  use GenServer
  require Logger

  # TODO: move this to config
  @allowed_files ["blacklist.json", "network.json", "credentials.json"]

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init the GenServer with an empty state.
  """
  def init(_) do
    {:ok, %{}}
  end

  # We write data to a specific file
  def handle_cast({:write, data, file}, s) when file in @allowed_files do
    case File.write(file, Jason.encode!(data)) do
      :ok ->
        {:noreply, s}
      {:error, _} ->
        {:noreply, s}
    end
  end

  # We read data from a specific file
  def handle_call({:read, file}, _from, s) when file in @allowed_files do
    case File.read(file) do
      {:ok, data} ->
        {:reply, Jason.decode!(data), s}
      {:error, _} ->
        {:reply, {:error, "There was a problem reading the file"}, s}
    end
  end

  # helper functions to call the process functions
  def write(data, file), do: GenServer.cast(__MODULE__, {:write, data, file})
  def read(file), do: GenServer.call(__MODULE__, {:read, file})
end

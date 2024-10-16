defmodule Sentinel.Servers.File do
  @moduledoc """
  Write to files and read from files.
  """
  use GenServer
  require Logger

  # TODO: move this to config
  @allowed_files ["blacklist.json", "network.json", "credentials.json"]
  @data_dir "data/"

  # TODO: make sure to get default values from the config

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init the GenServer with an empty state.
  """
  def init(_) do
    # init the files
    # TODO: add under the /data directory and populate defailt values for files
    __MODULE__.write(%{}, "blacklist.json")
    __MODULE__.write(%{}, "network.json")
    __MODULE__.write(%{}, "credentials.json")

    {:ok, %{}}
  end

  # We write data to a specific file
  def handle_cast({:write, data, file}, s) when file in @allowed_files do
    # TODO: get the data and we want to merge to the file, not overwrite
    case File.write(@data_dir <> file, Jason.encode!(data)) do
      :ok ->
        {:noreply, s}
      {:error, _} ->
        {:noreply, s}
    end
  end

  # We read data from a specific file
  def handle_call({:read, file}, _from, s) when file in @allowed_files do
    case File.read(@data_dir <> file) do
      {:ok, data} ->
        {:reply, Jason.decode!(data), s}
      {:error, _} ->
        {:reply, {:error, "There was a problem reading the file"}, s}
    end
  end

  # delete file
  def handle_call({:delete, file}, _, s) when file in @allowed_files do
    case File.rm(@data_dir <> file) do
      :ok ->
        {:reply, :ok, s}
      {:error, _} ->
        {:reply, {:error, "There was a problem deleting the file"}, s}
    end
  end

  # helper functions to call the process functions
  def write(data, file), do: GenServer.cast(__MODULE__, {:write, data, file})
  def read(file), do: GenServer.call(__MODULE__, {:read, file})
  def delete(file), do: GenServer.call(__MODULE__, {:delete, file})
end

defmodule Sentinel.Servers.Logs do
  @moduledoc """
  The log server managing logs of requests done through the system
  """
  use GenServer
  require Logger

  @interval 3_600_000 # 1h
  @topic "sentinel:logs"
  @log_dir System.user_home() <> "/logs"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init Logs
  """
  def init(_) do
    archived_files = fetch_archived_files()
    send(self(), :sync)

    {:ok,
     %{
       archived: %{
        files: archived_files,
        count: archived_files |> length()
       }
     }}
  end

  def handle_info(:sync, state) do
    archived_files = fetch_archived_files()

    archived_result = %{
      files: archived_files,
      count: archived_files |> length(),
    }

    # sync and return the archived logs data
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:archived_files, archived_result})

    # Refetch - recheck
    sync_archived_files()

    {:noreply, state}
  end

  # The job that will start interval sync
  defp sync_archived_files() do
    :timer.send_after(@interval, :sync)
  end

  # archived logs
  defp fetch_archived_files() do
    if Application.get_env(:sentinel, :mock_data, false) do
      Sentinel.Servers.FakeData.Logs.get_archived_files()
    else
      @log_dir |> File.ls!()
    end
  end

  @doc """
  Get all of the log information from the log file
  Note: for now the user needs to get everything
  """
  def handle_call({:get_state, refetch}, _from, state) when refetch === true do
    send(self(), :sync)
    {:reply, {:ok, state}, state}
  end
  def handle_call({:get_state, _refetch}, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @doc """
  Get all of the log information from the log file for a specific device
  """
  def handle_call({:get_device_logs, ip}, _from, state) do
    logs =
      if Application.get_env(:sentinel, :mock_data, false) do
        Sentinel.Servers.FakeData.Logs.get_device_data()
      else
        filter_queries_by_ip(ip)
        |> Enum.map(fn log ->
          # Match the log line with a regular expression
          case Regex.run(
                 ~r/^(\w+\s+\d+\s+\d+:\d+:\d+).*query\[(\w+)\]\s+([\w\.\-]+)\s+from\s+([\d\.]+)/,
                 log
               ) do
            [_, log_time, query_type, domain, log_ip] ->
              %{
                time: log_time,
                query_type: query_type,
                domain: domain,
                ip: log_ip
              }

            _ ->
              # Return a default map if parsing fails - we return the same data just t
              %{
                time: "!err",
                query_type: "!err",
                domain: "!err",
                ip: "!err"
              }
          end
        end)
      end

    {:reply, {:ok, logs}, state}
  end

  @doc """
  Delete the log file
  """
  def handle_call({:delete_log_file, file}, _from, state) do
    path = @log_dir <> "/" <> file
    case File.rm(path) do
      :ok ->
        {:reply, {:ok, "File deleted successfully"}, state}
      {:error, reason} ->
        {:reply, {:error, "Failed to delete file: #{inspect(reason)}"}, state}
    end
  end

  # filter by IP
  def filter_queries_by_ip(ip) do
    # Dynamically resolve the path to the logs directory one level up
    log_file = Path.expand("../logs/_dnsmasq.log", File.cwd!())

    case System.cmd("sh", ["-c", "grep -E 'query\\[A\\].*#{ip}' #{log_file} | tail -n 30 | tac"]) do
      {output, 0} ->
        String.split(output, "\n", trim: true)

      {_, 1} ->
        IO.puts("No matching queries found.")
        []

      {error, _} ->
        IO.puts("Error: #{error}")
        []
    end
  end

  # Get entire state details for the logs
  def get_state(), do: GenServer.call(__MODULE__, {:get_state, false})
  def init_state(), do: GenServer.call(__MODULE__, {:get_state, true})
  def get_device_logs(ip), do: GenServer.call(__MODULE__, {:get_device_logs, ip})
  def delete_log_file(file), do: GenServer.call(__MODULE__, {:delete_log_file, file})
end

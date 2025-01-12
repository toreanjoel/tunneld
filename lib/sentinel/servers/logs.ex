defmodule Sentinel.Servers.Logs do
  @moduledoc """
  The log server managing logs of requests done through the system
  """
  use GenServer
  require Logger

  # 2m
  @sync_data_interval 120_000
  # 1d
  # @backup_interval 86_400_000
  @backup_interval 10_000
  # @cleanup_interval 43200000 # 12h
  # 10s
  @cleanup_interval 30_000

  @topic "sentinel:logs"
  @log_file "_data.log"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init Logs
  """
  def init(_) do
    archived_files = fetch_archived_files()

    # Trigger the start of the processes that will run after set time to cleanup over time
    archive_log_file()
    cleanup_archived_files()

    {:ok,
     %{
       archived: %{
         files: archived_files,
         count: archived_files |> length()
       }
     }}
  end

  # The job that will start interval sync to fetch the current log file details
  def handle_info(:sync, state) do
    archived_files = fetch_archived_files()

    archived_result = %{
      files: archived_files,
      count: archived_files |> length()
    }

    # sync and return the archived logs data
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:archived_files, archived_result})

    # Refetch - recheck
    sync_archived_files()

    {:noreply, state}
  end

  # Handle questions to backup the current logs
  def handle_info(:backup_logs, state) do
    # Dynamically resolve the log file path
    log_path = Path.expand("../logs/" <> @log_file, File.cwd!())
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    # Compressed backup name
    backup_path = Path.expand("../logs/#{timestamp}.log.gz", File.cwd!())

    case get_file_size_mb(@log_file) do
      {:ok, size} when size > 5 ->
        # Copy the log file to a new file before compression
        System.cmd("cp", [log_path, String.replace_suffix(backup_path, ".gz", "")])

        # Compress the copied file
        System.cmd("gzip", [String.replace_suffix(backup_path, ".gz", "")])

        # Clear the original log file to continue logging
        System.cmd("truncate", ["-s", "0", log_path])

        # Restart the service explicitly (if needed)
        Sentinel.Servers.Services.restart_service(:dnsmasq)

        # Try the backup later again
        archive_log_file()
      _ ->
        # Return state unchanged
        :ok
      end

    {:noreply, state}
  end

  # Handle questions to remove old backup files
  def handle_info(:cleanup_logs, state) do
    # Delete the old log files that are older than a certain time relative to the current time - relies on the title of the fileW

    IO.inspect("Cleaning up the old log files")

    # Process archiving jobs later again
    cleanup_archived_files()

    # Return the current state as we dont need to change general data state
    {:noreply, state}
  end

  # Get all of the log information from the log file
  def handle_call({:get_state, refetch}, _from, state) when refetch === true do
    send(self(), :sync)
    {:reply, {:ok, state}, state}
  end

  def handle_call({:get_state, _refetch}, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # Get all of the log information from the log file for a specific device
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

  # Delete the log file
  def handle_call({:delete_log_file, file}, _from, state) do
    # Dynamically resolve the log file path
    path = Path.expand("../logs/" <> file, File.cwd!())

    case File.rm(path) do
      :ok ->
        {:reply, {:ok, "File deleted successfully"}, state}

      {:error, reason} ->
        {:reply, {:error, "Failed to delete file: #{inspect(reason)}"}, state}
    end
  end

  # filter by IP
  defp filter_queries_by_ip(ip) do
    # Dynamically resolve the path to the logs directory one level up
    log_file = Path.expand("../logs/" <> @log_file, File.cwd!())

    case System.cmd("sh", [
           "-c",
           "cat #{log_file} | grep -E 'query\\[A\\].*#{ip}' | tail -n 100 | tac"
         ]) do
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

  # archived logs
  defp fetch_archived_files() do
    # Dynamically resolve the log directory
    log_dir = Path.expand("../logs", File.cwd!())

    if Application.get_env(:sentinel, :mock_data, false) do
      Sentinel.Servers.FakeData.Logs.get_archived_files()
    else
      File.ls!(log_dir)
    end
  end

  # get the file size in MB
  defp get_file_size_mb(log_file) do
    log_file_path = Path.expand("../logs/" <> log_file, File.cwd!())

    case File.stat(log_file_path) do
      # Convert to MB
      {:ok, %File.Stat{size: size}} -> {:ok, size / 1_048_576}
      {:error, reason} -> {:error, "Failed to get file size: #{inspect(reason)}"}
    end
  end

  # The job that will start interval sync amake sure we have the latest data
  defp sync_archived_files() do
    :timer.send_after(@sync_data_interval, :sync)
  end

  # Backup the current log file based on some condition (file size?)
  defp archive_log_file() do
    :timer.send_after(@backup_interval, :backup_logs)
  end

  # The function that will be used to remove old archived or old files after n time
  defp cleanup_archived_files() do
    :timer.send_after(@cleanup_interval, :cleanup_logs)
  end

  # Get entire state details for the logs
  def get_state(), do: GenServer.call(__MODULE__, {:get_state, false})
  def init_state(), do: GenServer.call(__MODULE__, {:get_state, true})
  def get_device_logs(ip), do: GenServer.call(__MODULE__, {:get_device_logs, ip})
  def delete_log_file(file), do: GenServer.call(__MODULE__, {:delete_log_file, file})
end

defmodule Sentinel.Servers.Logs do
  @moduledoc """
  The log server managing logs of requests done through the system
  """
  use GenServer
  require Logger

  # We backup every 6 hours and attempt cleanup every day
  # The cleanup will check for files older than 7d
  @six_hours 21_600_000 # 6h
  @one_day 86_400 # 1d in seconds so we can make sure it works

  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details_desktop"
  @component_mobile_id "sidebar_details_mobile"
  @component_module SentinelWeb.Live.Components.Sidebar.Details

  @log_file "_data.log"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init Logs
  """
  def init(_) do
    archived_files = fetch_archived_files()

    archive_log_file()
    cleanup_archived_files()

    {:ok,
     %{
       archived: %{
         files: archived_files,
         count: length(archived_files)
       }
     }}
  end

  # The job that will start interval sync to fetch the current log file details
  def handle_info(:sync, state) do
    archived_files = fetch_archived_files()

    archived_result = %{
      files: archived_files,
      count: length(archived_files)
    }

    # Broadcast the new data structure for the sidebar component - desktop
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
      id: @component_desktop_id,
      module: @component_module,
      data: %{
        logs: archived_result
      }
    })
    # Broadcast the new data structure for the sidebar component - mobile
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
      id: @component_mobile_id,
      module: @component_module,
      data: %{
        logs: archived_result
      }
    })

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

      _ ->
        # Return state unchanged
        :ok
      end

    # Try the backup later again - regardless if it found or now
    archive_log_file()

    {:noreply, state}
  end

  # Handle questions to remove old backup files
  def handle_info(:cleanup_logs, state) do
    if Application.get_env(:sentinel, :mock_data, false) do
      {:noreply, state}
    else
      # Define log directory and get list of files
      log_dir = Path.expand("../logs/", File.cwd!())

      # Get current Unix timestamp
      current_time = DateTime.utc_now() |> DateTime.to_unix()

      # Get list of files in the log directory
      log_files = File.ls!(log_dir)

      # Filter and delete old log files
      Enum.each(log_files, fn filename ->
        case String.split(filename, ".") do
          [timestamp_str, "log", "gz"] ->
            # 3 array means it was a backup that was made
            timestamp = String.to_integer(timestamp_str)

            if current_time - timestamp > (@one_day * 7) do
              file_path = Path.join(log_dir, filename)
              case File.rm(file_path) do
                :ok -> IO.puts("Deleted old log file: #{filename}")
                {:error, reason} -> IO.puts("Failed to delete #{filename}: #{inspect(reason)}")
              end
              :ok
            end

          _ -> :ok # Skip non-matching files
        end
      end)

      cleanup_archived_files()

      {:noreply, state}
    end
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

    # Broadcast the new data structure for the sidebar component - desktop
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
      id: @component_desktop_id,
      module: @component_module,
      data: %{
        logs: logs
      }
    })
    # Broadcast the new data structure for the sidebar component - mobile
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
      id: @component_mobile_id,
      module: @component_module,
      data: %{
        logs: logs
      }
    })

    {:reply, {:ok, logs}, state}
  end

  # Delete the log file
  def handle_call({:delete_log_file, file}, _from, state) do
    # Dynamically resolve the log file path
    path = Path.expand("../logs/" <> file, File.cwd!())

    case File.rm(path) do
      :ok ->
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{ type: :info, message: "File deleted successfully"})
        init_state()
        {:reply, {:ok, "File deleted successfully"}, state}

      {:error, reason} ->
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{ type: :info, message: "Failed to delete file: #{inspect(reason)}"})
        init_state()
        {:reply, {:error, "Failed to delete file: #{inspect(reason)}"}, state}
    end
  end

  # Get all of the log information from the log file
  def handle_cast(:init_state, state) do
    send(self(), :sync)
    {:noreply, state}
  end

  # filter by IP
  defp filter_queries_by_ip(ip) do
    # Dynamically resolve the path to the logs directory one level up
    log_file = Path.expand("../logs/" <> @log_file, File.cwd!())

    case System.cmd("sh", ["-c", "tail -n 1000 #{log_file} | grep -E 'query\\[A\\].*#{ip}'"]) do
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

  # Backup the current log file based on some condition (file size?)
  defp archive_log_file() do
    :timer.send_after(@six_hours, :backup_logs)
  end

  # The function that will be used to remove old archived or old files after n time
  defp cleanup_archived_files() do
    :timer.send_after(@one_day, :cleanup_logs)
  end

  # Get entire state details for the logs
  def init_state(), do: GenServer.cast(__MODULE__, :init_state)
  def get_device_logs(ip), do: GenServer.call(__MODULE__, {:get_device_logs, ip})
  def delete_log_file(file), do: GenServer.call(__MODULE__, {:delete_log_file, file})
end

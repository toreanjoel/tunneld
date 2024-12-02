defmodule Sentinel.Servers.Logs do
  @moduledoc """
  The log server managing logs of requests done through the system
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init Logs
  """
  def init(_) do
    {:ok, %{}}
  end

  @doc """
  Get all of the log information from the log file
  Note: for now the user needs to get everything
  """
  def handle_call(:get_state, _from, state) do
    # TODO: Get the logs
    {:reply, {:ok, state}, state}
  end

  def handle_call({:get_logs, ip}, _from, state) do
    logs = if Application.get_env(:sentinel, :mock_data, false) do
      Sentinel.Servers.FakeData.Logs.get_data()
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
            # Return a default map if parsing fails
            %{error: "Invalid log format", raw: log}
        end
      end)
    end
    {:reply, {:ok, logs}, state}
  end

  # filter by IP
  def filter_queries_by_ip(ip) do
    # Dynamically resolve the path to the logs directory one level up
    log_file = Path.expand("../logs/dnsmasq.log", File.cwd!())

    case System.cmd("grep", ["-E", "query\\[A\\].*#{ip}", log_file]) do
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
  def get_state(), do: GenServer.call(__MODULE__, :get_state)
  def get_logs(ip), do: GenServer.call(__MODULE__, {:get_logs, ip})
end

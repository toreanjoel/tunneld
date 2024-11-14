defmodule Sentinel.Servers.Overview do
  @moduledoc """
  Get the overview data of all services to display on the dashboard
  """
  use GenServer
  require Logger
  alias Sentinel.Servers.Broadcast

  # Interval check - 60 seconds
  @interval 60_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Initialize the session state and start check interval.
  """
  def init(_) do
    # Base state
    state = %{
      services: %{
        dnsmasq: 0,
        dhcpcd: 0,
        hostapd: 0,
      },
      count: %{
        logs: 0,
        blacklist: 0,
        devices: 0,
      },
      network: %{
        speed: 0,
        latency: 0,
      },
      updated_at: DateTime.utc_now() |> to_string,
    }

    # init and start the process
    send(self(), :sync)

    {:ok, state}
  end

  # Periodically clean up expired sessions
  def handle_info(:sync, state) do
    current_time = DateTime.utc_now() |> to_string

    # Here we make calls to other services for their data
    state = state
      |> Map.put(:services, get_statuses())
      |> Map.put(:count, get_counts())
      |> Map.put(:network, get_network())
      |> Map.put(:updated_at, current_time)

    # We need to send the event to the topic - we reference what we just got
    Broadcast.System.emit({:dashboard_updated_at, current_time})
    Broadcast.System.emit({:dashboard_network, state.network})
    Broadcast.System.emit({:dashboard_services, state.services})
    Broadcast.System.emit({:dashboard_count, state.count})

    sync_overview()
    {:noreply, state}
  end

  @doc """
  Get the overview data
  """
  def handle_call(:get, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # Schedule the next cleanup using :timer.send_after
  defp sync_overview() do
    :timer.send_after(@interval, :sync)
  end

  # Get service status - TODO: create separate servers here for this
  defp get_statuses() do
    %{
      dnsmasq: Enum.random(0..1),
      dhcpcd: Enum.random(0..1),
      hostapd: Enum.random(0..1)
    }
  end

  # Get service count - TODO: create separate servers here for this
  defp get_counts() do
    %{
      logs: Enum.random(1..30_000),
      blacklist: Enum.random(1..30_000),
      devices: Enum.random(1..99),
    }
  end

  # Get Network details - TODO: create separate servers here for this
  defp get_network() do
    {_, resp} = Sentinel.Servers.Network.get_all()
    resp
  end

  # Get the overview data
  def get(), do: GenServer.call(__MODULE__, :get)
end

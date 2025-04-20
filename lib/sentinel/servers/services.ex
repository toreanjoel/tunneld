defmodule Sentinel.Servers.Services do
  @moduledoc """
  Manage running services
  """
  use GenServer
  require Logger

  @services [:dnsmasq, :dhcpcd, :'dnscrypt-proxy']
  @service_log_limit "25"
  @interval 20_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init services
  """
  def init(_) do
    send(self(), :sync)
    {:ok, %{}}
  end

  @doc """
  Get the system logs for the services that we can render
  """
  def handle_call({:get_service_logs, service}, _from, state) do
    service_atom = service |> String.to_atom

    if service_atom in @services do
      data = case System.cmd("journalctl", ["-u", service |> to_string, "-n", @service_log_limit, "--no-pager"]) do
        {resp, 0} -> resp
        _ ->
          "There was an error fetching the service logs"
      end

      data = data |> String.split("\n") |> Enum.filter(fn item -> item !== "" end) |> Enum.reverse()

      # Broadcast to sidebar details for desktop:
      Phoenix.PubSub.broadcast(Sentinel.PubSub, "component:details", %{
        id: "sidebar_details_desktop",
        module: SentinelWeb.Live.Components.Sidebar.Details,
        data: %{
          logs: data
        }
      })

      # Broadcast to sidebar details for mobile:
      Phoenix.PubSub.broadcast(Sentinel.PubSub, "component:details", %{
        id: "sidebar_details_mobile",
        module: SentinelWeb.Live.Components.Sidebar.Details,
        data: %{
          logs: data
        }
      })

      {:reply, {:ok, data}, state}
    else
      Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{ type: :error, message: "Make sure the service selected is allowed"})
      {:reply, {:error, "Make sure the service selected is allowed"}, state}
    end
  end

  # Restart a service
  def handle_cast({:restart_service, service}, state) do
    service_name = service |> to_string

    Task.start(fn ->
      System.cmd("systemctl", ["restart", service_name])
    end)
    Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{ type: :error, message: "Restarting serice: #{service_name}"})
    {:noreply, state}
  end

  # get the data and restart sync
  def handle_info(:sync, state) do
    result = Enum.reduce(@services, %{}, fn service, acc ->
      Map.put(acc, service, check_service(service))
    end)

    # Broadcast to sidebar details for desktop:
    Phoenix.PubSub.broadcast(Sentinel.PubSub, "component:services", %{
      id: "services",
      module: SentinelWeb.Live.Components.Services,
      data: %{
        status: result
      }
    })

    sync_services()
    {:noreply, Map.merge(state, result)}
  end

  # The job that will start interval sync
  defp sync_services() do
    :timer.send_after(@interval, :sync)
  end

  # check if services is running
  defp check_service(service) do
    try do
      {output, _exit_code} = System.cmd("systemctl", ["is-active", service |> to_string])
      is_active = String.trim(output) == "active"

      if !is_active do
        System.cmd("systemctl", ["start", service |> to_string])
      end

      is_active
    rescue
      _ ->
        false
    end
  end

  # Public API
  def get_service_logs(service), do: GenServer.call(__MODULE__, {:get_service_logs, service})
  def restart_service(service), do: GenServer.cast(__MODULE__, {:restart_service, service})
end

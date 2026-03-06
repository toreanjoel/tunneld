defmodule Tunneld.Servers.Services do
  @moduledoc """
  Manage running services
  """
  use GenServer
  require Logger

  @services [:dnsmasq, :dhcpcd, :"dnscrypt-proxy", :nginx]
  @service_log_limit "25"
  @interval 10_000

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
    service_atom = Enum.find(@services, fn s -> to_string(s) == service end)

    try do
      if service_atom do
        data =
          case System.cmd("journalctl", [
                 "-u",
                 service |> to_string,
                 "-n",
                 @service_log_limit,
                 "--no-pager"
               ]) do
            {resp, 0} ->
              resp

            _ ->
              "There was an error fetching the service logs"
          end

        data =
          data |> String.split("\n") |> Enum.filter(fn item -> item !== "" end) |> Enum.reverse()

        # Broadcast to sidebar details for desktop:
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:details", %{
          id: "sidebar_details",
          module: TunneldWeb.Live.Components.Sidebar.Details,
          data: %{
            service: service_atom,
            logs: data
          }
        })

        {:reply, {:ok, data}, state}
      else
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Make sure the service selected is allowed"
        })

        {:reply, {:error, "Make sure the service selected is allowed"}, state}
      end
    rescue
      _ ->
        {:reply, {:ok, ""}, state}
    end
  end

  # Restart a service - can be broken to be more modular
  def handle_cast({:restart_service, service, :no_notify}, state) do
    service_name = service |> to_string

    Task.start(fn ->
      System.cmd("systemctl", ["restart", service_name])
    end)

    {:noreply, state}
  end

  def handle_cast({:restart_service, service}, state) do
    service_name = service |> to_string

    Task.start(fn ->
      System.cmd("systemctl", ["restart", service_name])
    end)

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: :info,
      message: "Restarting service: #{service_name}"
    })

    {:noreply, state}
  end

  # get the data and restart sync
  def handle_info(:sync, state) do
    result =
      Enum.reduce(@services, %{}, fn service, acc ->
        Map.put(acc, service, check_service(service))
      end)

    # Broadcast to sidebar details for desktop:
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:services", %{
      id: "services",
      module: TunneldWeb.Live.Components.Services,
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

  def restart_service(service, :no_notify),
    do: GenServer.cast(__MODULE__, {:restart_service, service, :no_notify})
end

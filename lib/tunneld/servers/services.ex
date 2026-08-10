defmodule Tunneld.Servers.Services do
  @moduledoc """
  Monitors and manages the core system services (dnsmasq, dhcpcd, caddy).
  """
  use GenServer
  require Logger

  @services [:dnsmasq, :dhcpcd, :caddy]
  @interval 10_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    send(self(), :sync)
    {:ok, %{}}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:restart_service, service, :no_notify}, state) do
    if service in @services do
      service_name = to_string(service)

      Task.start(fn ->
        System.cmd("systemctl", ["restart", service_name])
      end)
    end

    {:noreply, state}
  end

  def handle_cast({:restart_service, service}, state) do
    if service in @services do
      service_name = to_string(service)

      Task.start(fn ->
        System.cmd("systemctl", ["restart", service_name])
      end)

      Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
        type: :info,
        message: "Restarting service: #{service_name}"
      })
    else
      Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
        type: :error,
        message: "Unknown service: #{inspect(service)}"
      })
    end

    {:noreply, state}
  end

  def handle_info(:sync, state) do
    result =
      Enum.reduce(@services, %{}, fn service, acc ->
        Map.put(acc, service, check_service(service))
      end)

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

  defp sync_services() do
    :timer.send_after(@interval, :sync)
  end

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

  @doc "Returns the current status of all monitored services."
  @spec get_status :: %{atom() => boolean()}
  def get_status do
    try do
      GenServer.call(__MODULE__, :get_status)
    catch
      :exit, _ -> %{}
    end
  end

  def restart_service(service), do: GenServer.cast(__MODULE__, {:restart_service, service})

  def restart_service(service, :no_notify),
    do: GenServer.cast(__MODULE__, {:restart_service, service, :no_notify})
end

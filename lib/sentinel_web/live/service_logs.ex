defmodule SentinelWeb.Live.ServiceLogs do
  @moduledoc """
  Service Logs Page - This is to get the details of logs specific to the service
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Services}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Get the serice in question that will be rendered
  """
  def mount(%{"service" => service}, %{"ip" => ip} = _session, socket) do
    socket =
      socket
      |> assign(:ip, ip)
      |> assign(:logs, [])
      |> assign(:service, service)
      |> assign(:count, 0)

    send(self(), :init)
    {:ok, socket}
  end

  @doc """
  Render the service Logs
  """
  def render(assigns) do
    ~H"""
    <Navigation.show id="nav" align="start">
      <div class="text-left w-full">
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Service Logs: <%= @service %>
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 gap-1 text-sm text-gray-600 flex flex-row items-center">
          <div class="grow">
            The logs for the service on the operating system, used for debugging and getting metrics on the system service itself
          </div>
          <button
            phx-click="refresh"
            class="px-3 py-1 bg-blue-500 text-white rounded"
          >
            Refresh
          </button>
          <button
            phx-click="restart_service"
            class="px-3 py-1 bg-red-500 text-white rounded"
          >
            Restart
          </button>
        </div>
        <hr class="my-3 border-dashed border-gray-300" />

        <p :if={@count == 0} class="text-gray-500">No Service Logs</p>
        <div :if={@count > 0} class="overflow-x-auto">
          <table class="table-auto border-collapse border border-gray-200 w-full text-gray-600">
            <tbody>
              <%= for log <- @logs do %>
                <tr>
                  <td class="border border-gray-300 px-4 py-2">
                    <%= log %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </Navigation.show>
    """
  end

  @doc """
  Handle form validation on input change
  """
  def handle_event("logout", _, socket) do
    # TODO: we need to consider doing a modal over here
    Session.delete(socket.assigns.ip)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
  end

  # refresh the lists
  def handle_event("refresh", _p, socket) do
    send(self(), :init)
    {:noreply, socket}
  end

  # Restart the service
  def handle_event("restart_service", _p, socket) do
    service = socket.assigns.service

    # Restart the specific service on the operating sytem
    Services.restart_service(service |> String.to_atom())

    # Reinit auto after a few seconds
    Process.send_after(self(), :init, 2_000)

    {:noreply, socket}
  end

  # get the devices for the current devices connect
  def handle_info(:init, socket) do
    {status, data} = Services.get_logs(socket.assigns.service)

    socket =
      case status do
        :error ->
          socket
          |> assign(:logs, [])
          |> assign(:count, 0)

        _ ->
          socket
          |> assign(:logs, data)
          |> assign(:count, data |> length)
      end

    {:noreply, socket}
  end
end

defmodule SentinelWeb.Live.DeviceDetails do
  @moduledoc """
  Device details
  """
  use SentinelWeb, :live_view
  alias SentinelWeb.Components.Navigation

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  def mount(params, _session, socket) do
    # TODO: fetch logs for IP
    send(self(), :init)

    socket =
      socket
      |> assign(:ip, params["ip"])
      |> assign(:logs, [])
      |> assign(:loading, true)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Navigation.show id="nav" align="start">
      <div class="text-left w-full">
        <.back navigate={~p"/devices"}>Back to devices</.back>
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Logs: <%= @ip %>
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 text-sm text-gray-600 flex flex-row items-center">
          <div class="grow">
            The logs for the current device connected
          </div>
          <div phx-click="refresh" class="cursor-pointer hover:bg-white p-1 hover:rounded-lg transition-all duration-500">
            <.icon name="hero-arrow-path" class="h-5 w-5" />
          </div>
        </div>
        <hr class="my-3 border-dashed border-gray-300" />

        <div :if={@loading}>
          Loading...
        </div>
        <div :if={@logs == [] and not @loading}>
          No logs found
        </div>
        <div :if={@logs != [] and not @loading}>
          <table class="table-auto border-collapse border border-gray-200 w-full">
            <thead>
              <tr class="bg-gray-100">
                <th class="border border-gray-300 px-4 py-2 text-left">Time</th>
                <th class="border border-gray-300 px-4 py-2 text-left">Query Type</th>
                <th class="border border-gray-300 px-4 py-2 text-left">Domain</th>
              </tr>
            </thead>
            <tbody>
              <%= for log <- @logs do %>
                <tr class="hover:bg-gray-50 cursor-pointer">
                  <td class="border border-gray-300 px-4 py-2"><%= log.time %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= log.query_type %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= log.domain %></td>
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
    Fetch the logs for the current device
  """
  def handle_info(:init, socket) do
    {_, logs} = Sentinel.Servers.Logs.get_device_logs(socket.assigns.ip)
    socket =
      socket
      |> assign(:logs, logs |> Enum.reverse())
      |> assign(:loading, false)
    {:noreply, socket}
  end

  # refresh the lists
  def handle_event("refresh", _p, socket) do
    send(self(), :init)
    {:noreply, socket}
  end
end

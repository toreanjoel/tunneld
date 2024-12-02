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

    socket = socket
      |> assign(:ip, params["ip"])
      |> assign(:logs, [])

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Navigation.show id="nav" align="center">
      <div class="text-left w-full">
        <.back navigate={~p"/devices"}>Back to devices</.back>
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Device Logs
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 text-sm text-gray-600">
          The logs for the current device connected to the ip address <%= @ip %>
        </div>
        <hr class="my-3 border-dashed border-gray-300" />

        <div :if={@logs == []}>
          No logs found
        </div>
        <div :if={@logs != []}>
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
    {_, logs} = Sentinel.Servers.Logs.get_logs(socket.assigns.ip)
    socket = socket
      |> assign(:logs, logs)
    {:noreply, socket}
  end
end

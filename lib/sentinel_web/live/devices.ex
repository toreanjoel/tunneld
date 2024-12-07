defmodule SentinelWeb.Live.Devices do
  @moduledoc """
  Devices Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Devices}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the Devices
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    # connect to the system broadcast channel topic
    SentinelWeb.Endpoint.subscribe("sentinel:devices")

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(:devices, [])
      |> assign(:count, 0)

    send(self(), :init)

    {:ok, socket}
  end

  @doc """
  Render the Devices
  """
  def render(assigns) do
    ~H"""
    <Navigation.show id="nav" align="start">
      <div class="text-left w-full">
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Connected Devices
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 text-sm text-gray-600">
          The devices and their assigned or leased IP addresses on the system currently
        </div>
        <hr class="my-3 border-dashed border-gray-300" />

        <p :if={@count == 0} class="text-gray-500">No devices connected</p>
        <div :if={@count > 0} class="overflow-x-auto">
          <table class="table-auto border-collapse border border-gray-200 w-full">
            <thead>
              <tr class="bg-gray-100">
                <th class="border border-gray-300 px-4 py-2 text-left">IP</th>
                <th class="border border-gray-300 px-4 py-2 text-left">Client ID</th>
                <th class="border border-gray-300 px-4 py-2 text-left">MAC Address</th>
                <th class="border border-gray-300 px-4 py-2 text-left">Name</th>
                <th class="border border-gray-300 px-4 py-2 text-left">Expiry</th>
              </tr>
            </thead>
            <tbody>
              <%= for device <- @devices do %>
                <tr
                  class="hover:bg-gray-50 cursor-pointer"
                  phx-click="navigate"
                  phx-value-ip={device.ip}
                >
                  <td class="border border-gray-300 px-4 py-2"><%= device.ip %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= device.client_id %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= device.mac_addr %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= device.host_name %></td>
                  <td class="border border-gray-300 px-4 py-2">
                    <%= DateTime.from_unix!(String.to_integer(device.expiry)) |> DateTime.to_string() %>
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
  TODO: move this to the nav component
  """
  def handle_event("logout", _, socket) do
    # TODO: we need to consider doing a modal over here
    Session.delete(socket.assigns.ip)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
  end

  # Handles navigation when a table row is clicked.
  def handle_event("navigate", %{"ip" => ip}, socket) do
    {:noreply,
     push_navigate(socket, to: Routes.live_path(socket, SentinelWeb.Live.DeviceDetails, ip))}
  end

  # get the devices for the current devices connect
  def handle_info(:init, socket) do
    {_, devices_state} = Devices.get_state()

    socket =
      socket
      |> assign(:devices, devices_state.devices)
      |> assign(:count, devices_state.count)

    {:noreply, socket}
  end

  # The general updates from polling system data
  def handle_info({:device_info, msg}, socket) do
    socket =
      socket
      |> assign(:devices, msg.devices)
      |> assign(:count, msg.count)

    {:noreply, socket}
  end
end

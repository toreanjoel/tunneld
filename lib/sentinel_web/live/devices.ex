defmodule SentinelWeb.Live.Devices do
  @moduledoc """
  Devices Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Devices, Whitelist}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the Devices
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    SentinelWeb.Endpoint.subscribe("sentinel:devices")

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(:devices, [])
      |> assign(:count, 0)
      |> assign(:whitelist, [])
      |> assign(:whitelist_count, 0)

    send(self(), :init)

    {:ok, socket}
  end

  # Unsubscribe from pubsub
  def terminate(_reason, _state) do
    SentinelWeb.Endpoint.unsubscribe("sentinel:devices")
    IO.puts("Unsubscribed from PubSub")
    :ok
  end

  @doc """
  Render the Devices + Whitelisted Devices
  """
  def render(assigns) do
    ~H"""
    <Navigation.show id="nav" align="start">
      <div class="text-left w-full">
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Connected Devices
        </div>
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
                  <td class="border border-gray-300 px-4 py-2"><%= device.mac %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= device.hostname %></td>
                  <td class="border border-gray-300 px-4 py-2">
                    <%= DateTime.from_unix!(String.to_integer(device.expiry)) |> DateTime.to_string() %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <hr class="my-3 border-dashed border-gray-300" />

        <div class="text-2xl font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Whitelisted Devices (Access Granted)
        </div>
        <p :if={@whitelist_count == 0} class="text-gray-500 mt-2">No devices have internet access.</p>
        <div :if={@whitelist_count > 0} class="overflow-x-auto">
          <table class="table-auto border-collapse border border-gray-200 w-full mt-3">
            <thead>
              <tr class="bg-gray-100">
                <th class="border border-gray-300 px-4 py-2 text-left">IP</th>
                <th class="border border-gray-300 px-4 py-2 text-left">MAC Address</th>
                <th class="border border-gray-300 px-4 py-2 text-left">Name</th>
                <th class="border border-gray-300 px-4 py-2 text-left">TTL</th>
                <th class="border border-gray-300 px-4 py-2 text-left">Action</th>
              </tr>
            </thead>
            <tbody>
              <%= for device <- @whitelist do %>
                <tr class="hover:bg-gray-50">
                  <td class="border border-gray-300 px-4 py-2"><%= device["ip"] %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= device["mac"] %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= device["hostname"] %></td>
                  <td class="border border-gray-300 px-4 py-2"><%= device["ttl"] %></td>
                  <td class="border border-gray-300 px-4 py-2">
                    <button
                      phx-click="revoke_access"
                      phx-value-mac={device["mac"]}
                      class="px-3 py-1 bg-red-500 text-white rounded"
                    >
                      Revoke Access
                    </button>
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
  Handle events
  """
  def handle_event("logout", _, socket) do
    Session.delete(socket.assigns.ip)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
  end

  def handle_event("navigate", %{"ip" => ip}, socket) do
    {:noreply, push_navigate(socket, to: Routes.live_path(socket, SentinelWeb.Live.DeviceDetails, ip))}
  end

  def handle_event("revoke_access", %{"mac" => mac}, socket) do
    IO.puts("Revoking access for MAC: #{mac}")
    Whitelist.remove_device_access(mac)
    send(self(), :init)
    {:noreply, socket}
  end

  @doc """
  Initialize data
  """
  def handle_info(:init, socket) do
    {_, devices_state} = Devices.get_state()
    {_, whitelist_data} = Whitelist.get_whitelist_page(0, 100)  # Load all whitelist data

    socket =
      socket
      |> assign(:devices, devices_state.devices)
      |> assign(:count, devices_state.count)
      |> assign(:whitelist, whitelist_data.data)
      |> assign(:whitelist_count, length(whitelist_data.data))

    {:noreply, socket}
  end

  def handle_info({:device_info, msg}, socket) do
    {_, whitelist_data} = Whitelist.get_whitelist_page(0, 100)

    socket =
      socket
      |> assign(:devices, msg.devices)
      |> assign(:count, msg.count)
      |> assign(:whitelist, whitelist_data.data)
      |> assign(:whitelist_count, length(whitelist_data.data))

    {:noreply, socket}
  end
end

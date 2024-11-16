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
    <Navigation.show id="nav">
      <div class="text-left">
        <h2>Devices</h2>
        <p :if={@count > 0}>No devices connected</p>

        <div :if={@count == 0}>
          <%= for device <- @devices do %>
            <%= Jason.encode!(device) %>
          <% end %>
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

defmodule SentinelWeb.Live.Dashboard do
  @moduledoc """
  Dashboard Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Services, Devices}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the dashboard
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    # connect to the system broadcast channel topics
    SentinelWeb.Endpoint.subscribe("sentinel:devices")
    SentinelWeb.Endpoint.subscribe("sentinel:services")

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(
        :overview_content,
        "Note: Processes to fetch network information will happen later in the lifecycle of starting the sytem"
      )
      |> assign(:updated_at, updated_at())
      |> assign(:services, %{
        dnsmasq: false,
        dhcpcd: false,
        hostapd: false,
        'dnscrypt-proxy': false
      })
      |> assign(:count, %{
        devices: 0
      })

    # Get base details here to init the application with
    send(self(), :init)

    {:ok, socket}
  end

  # unsubsroce from the pubsub
  def terminate(_reason, _state) do
    SentinelWeb.Endpoint.unsubscribe("sentinel:devices")
    SentinelWeb.Endpoint.unsubscribe("sentinel:services")
    IO.puts("Unsubscribed from PubSub")
    :ok
  end

  @doc """
  Render the dashboard
  """
  def render(%{services: services} = assigns) do
    hostapd_status = if !is_nil(services.hostapd) and services.hostapd, do: "good", else: "bad"
    dns_status = if !is_nil(services.dnsmasq) and services.dnsmasq, do: "good", else: "bad"
    dhcpcd_status = if !is_nil(services.dhcpcd) and services.dhcpcd, do: "good", else: "bad"
    dnscrypt_status = if !is_nil(services[:'dnscrypt-proxy']) and services[:'dnscrypt-proxy'], do: "good", else: "bad"

    assigns =
      assigns
      |> assign(:hostapd_status, hostapd_status)
      |> assign(:dns_status, dns_status)
      |> assign(:dhcpcd_status, dhcpcd_status)
      |> assign(:dnscrypt_status, dnscrypt_status)

    ~H"""
    <Navigation.show id="nav">
      <div class="text-left">
        <%!-- Welcome message --%>
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Hi there, <%= Application.get_env(:sentinel, :auth)[:user] |> String.capitalize() %>! <br />
          Here's your system overview
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 text-sm text-gray-600"><%= @overview_content %></div>
        <hr class="my-3 border-dashed border-gray-300" />

        <%!-- Basic badges --%>
        <div class="py-1 text-xs text-gray-500 text-xs">Click the status badge for more details</div>
        <div class="flex flex-wrap flex-row gap-1 my-2">
          <div class="hover:cursor-pointer" phx-click="service_logs" phx-value-id="hostapd">
            <.status_badge title="WiFi Access Point" status={@hostapd_status} />
          </div>
          <div class="hover:cursor-pointer" phx-click="service_logs" phx-value-id="dnsmasq">
            <.status_badge title="DNS" status={@dns_status} />
          </div>
          <div class="hover:cursor-pointer" phx-click="service_logs" phx-value-id="dnscrypt-proxy">
            <.status_badge title="DoH" status={@dnscrypt_status} />
          </div>
          <div class="hover:cursor-pointer" phx-click="service_logs" phx-value-id="dhcpcd">
            <.status_badge title="Dhcpcd" status={@dnscrypt_status} />
          </div>
        </div>

        <hr class="my-3 border-dashed border-gray-300" />

        <%!-- Info boxes that are used to summary with values --%>

        <%!-- Row 1 --%>
        <div class="flex flex-wrap flex-col sm:flex-row gap-4 my-3">
          <.info_box title="Connected Devices" value={@count.devices} icon="device-phone-mobile" />
        </div>

        <%!-- Row 2 --%>
        <div class="flex flex-row gap-4 my-2">
          <%!-- Insert the other relevant info here --%>
        </div>

        <%!-- We can have --%>
        <div class="text-gray-500 text-xs">
          Last updated: <%= @updated_at %>
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

  # Navigate to the service level logs for the service
  def handle_event("service_logs", %{"id" => id}, socket) do
    {:noreply,
      socket
      |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.ServiceLogs, id))}
  end

  @doc """
  Handle the broadcast messages from the sentinel channel topics
  """
  def handle_info({:device_info, msg}, socket) do
    updated_count = Map.merge(socket.assigns.count, %{devices: msg.count})

    socket =
      socket
      |> assign(:count, updated_count)
      |> assign(:updated_at, updated_at())

    {:noreply, socket}
  end

  # The services and updates to their status
  def handle_info({:services_info, msg}, socket) do
    socket =
      socket
      |> assign(:services, msg)
      |> assign(:updated_at, updated_at())

    {:noreply, socket}
  end

  # Handle the init of the application
  def handle_info(:init, socket) do
    # Get the base data
    {_, services} = Services.get_state()
    {_, devices} = Devices.get_state()

    # Set the base init data
    socket =
      socket
      |> assign(:updated_at, updated_at())
      |> assign(:services, services)
      |> assign(:count, %{
        devices: devices.count
      })

    {:noreply, socket}
  end

  # The updated at date for the ts when syncing happens
  defp updated_at() do
    DateTime.utc_now() |> to_string
  end
end

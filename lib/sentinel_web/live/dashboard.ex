defmodule SentinelWeb.Live.Dashboard do
  @moduledoc """
  Dashboard Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Logs, Blacklist, Services, Network, Devices}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the dashboard
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    # connect to the system broadcast channel topics
    SentinelWeb.Endpoint.subscribe("sentinel:network")
    SentinelWeb.Endpoint.subscribe("sentinel:logs")
    SentinelWeb.Endpoint.subscribe("sentinel:devices")
    SentinelWeb.Endpoint.subscribe("sentinel:blacklist")
    SentinelWeb.Endpoint.subscribe("sentinel:services")

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(
        :overview_content,
        "Systems are running well."
      )
      |> assign(:updated_at, updated_at())
      |> assign(:network, %{
        d_speed: 0,
        u_speed: 0,
        latency: 0,
        isp: nil
      })
      |> assign(:services, %{
        dnsmasq: false,
        dhcpcd: false,
        hostapd: false
      })
      |> assign(:count, %{
        logs: 0,
        blacklist: 0,
        devices: 0
      })

    # Get base details here to init the application with
    send(self(), :init)

    {:ok, socket}
  end

  @doc """
  Render the dashboard
  """
  def render(%{services: services, network: network} = assigns) do
    hostapd_status = if !is_nil(services.hostapd) and services.hostapd, do: "good", else: "bad"
    dns_status = if !is_nil(services.dnsmasq) and services.dnsmasq, do: "good", else: "bad"
    latency = if !is_nil(network.latency) and network.latency < 80, do: "good", else: "bad"

    assigns =
      assigns
      |> assign(:hostapd_status, hostapd_status)
      |> assign(:dns_status, dns_status)
      |> assign(:latency, latency)

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
        <div class="flex flex-wrap flex-row gap-1 my-2">
          <.status_badge title="WiFi Access Point" status={@hostapd_status} />
          <.status_badge title="DNS Server" status={@dns_status} />
          <.status_badge
            title={"Download: " <> to_string(@network.d_speed) <> " Mbps"}
            status={"info"}
          />
          <.status_badge
            title={"Upload: " <> to_string(@network.u_speed) <> " Mbps"}
            status={"info"}
          />
          <.status_badge
            title={"Latency: " <> to_string(@network.latency) <> " ms"}
            status={@latency}
          />
        </div>

        <hr class="my-3 border-dashed border-gray-300" />

        <%!-- Info boxes that are used to summary with values --%>

        <%!-- Row 1 --%>
        <div class="flex flex-wrap flex-col sm:flex-row gap-4 my-3">
          <.info_box title="Logs" value={@count.logs} icon="document" />
          <.info_box title="Connected Devices" value={@count.devices} icon="device-phone-mobile" />
          <.info_box title="Blacklisted Domains" value={@count.blacklist} icon="no-symbol" />
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

  @doc """
  Handle the broadcast messages from the sentinel channel topics
  """
  def handle_info({:network_info, msg}, socket) do
    socket =
      socket
      |> assign(:network, get_network_info(msg))
      |> assign(:updated_at, updated_at())
    {:noreply, socket}
  end

  # count update for blacklist_info
  def handle_info({:blacklist_info, msg}, socket) do
    updated_count = Map.merge(socket.assigns.count, %{blacklist: msg.count})
    socket =
      socket
      |> assign(:count, updated_count)
      |> assign(:updated_at, updated_at())

    {:noreply, socket}
  end

  # count update for log_info
  def handle_info({:log_info, msg}, socket) do
    updated_count = Map.merge(socket.assigns.count, %{log: msg.count})
    socket =
      socket
      |> assign(:count, updated_count)
      |> assign(:updated_at, updated_at())

    {:noreply, socket}
  end

  # count update for device_info
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
    {_, network} = Network.get_state()
    {_, logs} = Logs.get_state()
    {_, blacklist} = Blacklist.get_state()
    {_, services} = Services.get_state()
    {_, devices} = Devices.get_state()

    # Set the base init data
    socket =
      socket
      |> assign(:updated_at, updated_at())
      |> assign(:network, get_network_info(network))
      |> assign(:services, services)
      |> assign(:count, %{
        logs: logs.count,
        blacklist: blacklist.count,
        devices: devices.count
      })

    {:noreply, socket}
  end

  # The updated at date for the ts when syncing happens
  defp updated_at() do
    DateTime.utc_now() |> to_string
  end

  # get the relevant network information details
  defp get_network_info(network) do
    # bps to mbps
    conversion_value = 125000

    # Get the base data
    %{
      d_speed: network["download"]["bandwidth"] / conversion_value,
      u_speed: network["upload"]["bandwidth"] / conversion_value,
      latency: network["ping"]["latency"],
      isp: network["isp"],
    }
  end
end

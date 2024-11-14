defmodule SentinelWeb.Live.Dashboard do
  @moduledoc """
  Dashboard Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Broadcast}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the dashboard
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    # connect to the system broadcast channel topic
    Broadcast.System.topic(:info) |> SentinelWeb.Endpoint.subscribe()

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(
        :overview_content,
        "Systems are running well."
      )
      |> assign(:updated_at, "Not yet")
      |> assign(:network, %{
        speed: 0,
        latency: 0
      })
      |> assign(:services, %{
        dnsmasq: 0,
        dhcpcd: 0,
        hostapd: 0
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
  def render(assigns) do
    hostapd_status = if assigns.services.hostapd == 1, do: "good", else: "bad"
    dns_status = if assigns.services.dnsmasq == 1, do: "good", else: "bad"
    internet_speed_status = if assigns.network.speed > 0, do: "good", else: "bad"
    internet_latency_status = if assigns.network.latency < 24, do: "good", else: "bad"

    assigns =
      assigns
      |> assign(:hostapd_status, hostapd_status)
      |> assign(:dns_status, dns_status)
      |> assign(:internet_speed_status, internet_speed_status)
      |> assign(:internet_latency_status, internet_latency_status)

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
            title={"Speed: " <> to_string(@network.speed) <> " kbps"}
            status={@internet_speed_status}
          />
          <.status_badge
            title={"Latency: " <> to_string(@network.latency) <> "ms"}
            status={@internet_latency_status}
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
  Handle the broadcast from the sentinel channel
  """
  def handle_info({:info, msg}, socket) do
    case msg do
      {:dashboard_overview, content} ->
        {:noreply, assign(socket, :overview_content, content)}

      {:dashboard_updated_at, data} ->
        {:noreply, assign(socket, :updated_at, data)}

      {:dashboard_network, data} ->
        {:noreply, assign(socket, :network, data)}

      {:dashboard_services, data} ->
        {:noreply, assign(socket, :services, data)}

      {:dashboard_count, data} ->
        {:noreply, assign(socket, :count, data)}

      _ ->
        {:noreply, socket}
    end
  end

  @doc """
  Handle the init of the application
  """
  def handle_info(:init, socket) do
    # Get the base data
    {_, resp} = Sentinel.Servers.Overview.get()

    # Set the base init data
    socket =
      socket
      |> assign(:updated_at, resp.updated_at)
      |> assign(:network, resp.network)
      |> assign(:services, resp.services)
      |> assign(:count, resp.count)

    {:noreply, socket}
  end
end

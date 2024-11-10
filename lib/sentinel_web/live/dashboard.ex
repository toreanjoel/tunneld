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
    Broadcast.System.topic(:info) |> SentinelWeb.Endpoint.subscribe

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(:overview_content, "Systems are running well. Keep an eye on device 127.0.0.1 and their network usage.")
      |> assign(:overview_sync_ts, "Not yet")

    {:ok, socket}
  end

  @doc """
  Render the login form
  """
  def render(assigns) do
    ~H"""
    <Navigation.show id="nav">
      <div class="text-left">
        <%!-- Welcome message --%>
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Hi there, <%= Application.get_env(:sentinel, :auth)[:user] |> String.capitalize %>!
          <br />
          Here's your system overview
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 text-sm text-gray-600"><%= @overview_content %></div>
        <hr class="my-3 border-dashed border-gray-300" />

        <%!-- Basic badges --%>
        <div class="flex flex-wrap flex-row gap-1 my-2">
          <.status_badge title="WiFi Access Point" status="good" />
          <.status_badge title="DNS Server" status="bad" />
          <.status_badge title="Internet Speed" status="warning" />
          <.status_badge title="Internet Latency" status="warning" />
        </div>

        <hr class="my-3 border-dashed border-gray-300" />

        <%!-- Info boxes that are used to summary with values --%>

        <%!-- Row 1 --%>
        <div class="flex flex-wrap flex-col sm:flex-row gap-4 my-3">
          <.info_box title="Logs" value="25000" icon={"document"} />
          <.info_box title="Blocked Devices" value="3" icon={"x-circle"} />
          <.info_box title="Connected Devices" value="12" icon={"device-phone-mobile"} />
          <.info_box title="Blacklisted Domains" value="100" icon={"no-symbol"} />
        </div>

        <%!-- Row 2 --%>
        <div class="flex flex-row gap-4 my-2">
          <%!-- Insert the other relevant info here --%>
        </div>

        <%!-- We can have --%>
        <div class="text-gray-500 text-xs">
          Last updated: <%= @overview_sync_ts %>
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

  @doc """
  Handle the broadcast from the sentinel channel
  """
  def handle_info({:info, msg}, socket) do
    case msg do
      {:dashboard_overview, content} ->
        {:noreply, assign(socket, :overview_content, content)}
      {:dashboard_sync_ts, ts} ->
        {:noreply, assign(socket, :overview_sync_ts, ts)}
      _ ->
        {:noreply, socket}
    end
  end
end

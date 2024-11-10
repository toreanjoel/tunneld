defmodule SentinelWeb.Live.Dashboard do
  @moduledoc """
  Dashboard Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  # sentinel channels
  @sentinel_info "sentinel:info"

  @doc """
  Initialize the dashboard
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do

    # connect to the broadcast channel
    SentinelWeb.Endpoint.subscribe(@sentinel_info)

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
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-cyan-800 bg-clip-text text-transparent">
          Hi there, <%= Application.get_env(:sentinel, :auth)[:user] |> String.capitalize %>!
          <br />
          Here's your system overview
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 text-sm text-gray-600"><%= @overview_content %></div>
        <hr class="m-3 border-dashed border-gray-300" />
        <div>Status overview of basic services? (badges)</div>
        <div>Overview blocks of devices, speed, blocklist etc</div>

        <%!-- We can have --%>
        <div class="text-gray-500 text-sm">
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
  Handle the broadcast from the sentinel channel - content
  """
  def handle_info({:sentinel_info, {:dashboard_overview, content}}, socket) do
    {:noreply, assign(socket, :overview_content, content)}
  end

  @doc """
  Handle the broadcast from the sentinel channel - sync timestamp
  """
  def handle_info({:sentinel_info, {:dashboard_sync_ts, ts}}, socket) do
    {:noreply, assign(socket, :overview_sync_ts, ts)}
  end
end

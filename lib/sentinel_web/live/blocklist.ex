defmodule SentinelWeb.Live.Blacklist do
  @moduledoc """
  Blacklist Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the Blacklist
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do

    # connect to the system broadcast channel topic
    SentinelWeb.Endpoint.subscribe("sentinel:blacklist")

    socket =
      socket
      |> assign(:ip, ip)

    {:ok, socket}
  end

  @doc """
  Render the Blacklist
  """
  def render(assigns) do
    ~H"""
    <Navigation.show id="nav">
      <div class="text-left">
        <h2>Blacklist</h2>
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
end

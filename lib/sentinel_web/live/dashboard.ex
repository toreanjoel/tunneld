defmodule SentinelWeb.Live.Dashboard do
  @moduledoc """
  Dashboard Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session}
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the dashboard
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    socket = socket
      |> assign(:ip, ip)
    {:ok, socket}
  end

  @doc """
  Render the login form
  """
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center">
      <p class="text-2xl font-bold text-zinc-900">
        Dashboard
      </p>
      <.button class="mt-2" phx-click="logout">
        Logout
      </.button>
    </div>
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
end

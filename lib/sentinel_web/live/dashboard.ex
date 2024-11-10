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
    socket =
      socket
      |> assign(:ip, ip)

    {:ok, socket}
  end

  @doc """
  Render the login form
  """
  def render(assigns) do
    ~H"""
    <!-- NOTE: make a component that has the navigation -->
    <div class="flex flex-row lg:flex-row min-h-screen sm:height-screen">
      <!-- Navigation -->
      <div class="min-w-[50px] flex flex-col items-center py-3 border-r border-zinc-300">
        <!-- Navigation Icons with Hover Effect -->
        <div class="flex flex-col text-black">
          <div class="cursor-pointer hover:bg-white hover:rounded-lg p-2">
            <.icon name="hero-home" class="h-5 w-5" />
          </div>
          <div class="cursor-pointer hover:bg-white hover:rounded-lg p-2">
            <.icon
              name="hero-no-symbol"
              class="h-5 w-5"
            />
          </div>
          <div class="cursor-pointer hover:bg-white hover:rounded-lg p-2">
            <.icon
              name="hero-device-phone-mobile"
              class="h-5 w-5"
            />
          </div>
        </div>
        <!-- Spacer -->
        <div class="grow" />
        <!-- Settings Icons with Hover Effect -->
        <div class="flex flex-col text-black">
          <div class="cursor-pointer hover:bg-white hover:rounded-lg p-2">
            <.icon name="hero-cog" class="h-5 w-5" />
          </div>

          <%!-- Logout --%>
          <div phx-click="logout" class="cursor-pointer hover:bg-white hover:rounded-lg p-2">
            <.icon
              name="hero-arrow-right-end-on-rectangle"
              class="h-5 w-5"
            />
          </div>
        </div>
      </div>
      <!-- Main section -->
      <div class="flex flex-col grow items-center justify-center w-full lg:w-3/5 p-8">
        <p class="text-2xl font-bold text-zinc-900">
          Dashboard
        </p>
      </div>
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

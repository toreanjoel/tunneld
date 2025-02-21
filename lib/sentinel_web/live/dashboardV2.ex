defmodule SentinelWeb.Live.DashboardV2 do
  @moduledoc """
  Dashboard V2 Page
  """
  use SentinelWeb, :live_view
  alias SentinelWeb.Live.Components.{
    Welcome
  }

  # TODO: uncomment the line below to add auth into the system
  # on_mount SentinelWeb.Hooks.CheckAuth

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @doc """
  Initialize the dashboard with sidebar set to false.
  """
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        sidebar: %{
          is_open: false,
          details: nil
        }
      )

    {:ok, socket}
  end

  @doc """
  Render the dashboard.
  """
  def render(assigns) do
    ~H"""
    <div class="relative flex flex-row flex-1 h-screen text-white">
      <!-- Fixed width left column -->
      <%= nav(assigns) %>
      <!-- Flexible middle column -->
      <%= main(assigns) %>
      <!-- Sidebar for more details -->
      <%= sidebar(assigns) %>
    </div>
    """
  end

  #
  # ---- Views :: Components For Dashboard----
  #

  @spec sidebar(%{:sidebar => %{ is_open: boolean(), details: atom()}, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  @doc """
  The sidebar used for details around the selected conted
  """
  def sidebar(%{sidebar: sidebar} = assigns) do
    # set the assigns to render in the markup
    assigns =
      assigns
      |> assign(sidebar: sidebar)

    ~H"""
    <!-- Right panel: always visible on medium+ screens -->
    <div class="w-[30%] max-w-[600px] bg-primary hidden lg:block">
      <%= @sidebar.details %>
    </div>
    <!-- Right panel for small screens when toggled -->
    <div :if={@sidebar.is_open} class="absolute inset-0 bg-primary lg:hidden z-10">
      <!-- Close button in the overlay -->
      <button phx-click="toggle_sidebar" class="absolute top-4 right-4 bg-secondary p-2">
        Close
      </button>
      <div class="p-4">
        <%= @sidebar.details %>
      </div>
    </div>
    """
  end

  @spec main(any()) :: Phoenix.LiveView.Rendered.t()
  @doc """
  The main view content section
  """
  def main(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col bg-secondary h-full">
      <div class="h-[100px]">
        <!-- Toggle button for small screens only -->
        <button phx-click="toggle_sidebar" class="lg:hidden bg-secondary p-2 m-2">
          Open Sidebar
        </button>
      </div>
      <div class="border-2 border-solid border-primary"></div>
      <div class="flex flex-col flex-1">
        <%!-- Welcome section --%>
        <div>
          <.live_component id="welcome" module={Welcome} />
        </div>
        <%!-- Resources, Nodes and Services  --%>
        <div class="flex flex-col md:flex-row w-full h-full bg-opacity-40 bg-black">
          <div class="md:w-[50%] grow">Resources</div>
          <div class="md:w-[50%] flex flex-col grow">
            <div class="flex-1 grow">Nodes</div>
            <div class="flex-1 grow">Services</div>
          </div>
        </div>
        <%!-- Devices --%>
        <div class="min-h-[200px]">
          Devices
        </div>
      </div>
    </div>
    """
  end

  @spec nav(any()) :: Phoenix.LiveView.Rendered.t()
  @doc """
  Navigation used for general navigation (only logging in and out at the moment)
  """
  def nav(assigns) do
    ~H"""
    <div class="w-[50px] bg-primary flex flex-col justify-between p-3">
      <div class="grow" />
      <div class="flex items-center justify-center cursor-pointer">
        <.icon class="w-6 text-gray-2" name="hero-arrow-left-start-on-rectangle" />
      </div>
    </div>
    """
  end

  #
  # ---- Events :: Client Side Interaction ----
  #

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  Toggle the right panel visibility on small screens.
  """
  def handle_event("toggle_sidebar", _value, socket) do
    %{sidebar: sidebar} = socket.assigns

    sidebar = %{
      is_open: !Map.get(sidebar, :is_open),
      details: !Map.get(sidebar, :details)
    }

    {:noreply, assign(socket, :sidebar, sidebar)}
  end
end

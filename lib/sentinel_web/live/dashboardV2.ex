defmodule SentinelWeb.Live.DashboardV2 do
  @moduledoc """
  Dashboard V2 Page
  """
  use SentinelWeb, :live_view

  alias SentinelWeb.Live.Components.{
    Welcome,
    Resources,
    Services,
    Nodes,
    Devices
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
    <div class="relative flex flex-row flex-1 h-screen text-white overflow-auto bg-primary">
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

  @spec sidebar(%{:sidebar => %{is_open: boolean(), details: atom()}, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  @doc """
  The sidebar used for details around the selected conted
  """
  def sidebar(%{sidebar: sidebar} = assigns) do
    assigns = assign(assigns, :sidebar, sidebar)

    ~H"""
    <!-- Right panel: always visible on medium+ screens -->
    <div class="sticky inset-0 w-[30%] max-w-[600px] bg-secondary hidden lg:block">
      <%= @sidebar.details %>
    </div>
    <!-- Right panel for small screens when toggled -->
    <div :if={@sidebar.is_open} class="fixed inset-0 bg-primary lg:hidden z-10">
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
    <div class="flex-1 flex flex-col">
      <div class=" flex flex-row">
        <div class="flex-1">
          <!-- Toggle button for small screens only -->
          <button phx-click="toggle_sidebar" class="lg:hidden bg-secondary p-2 m-2">
            Open Sidebar
          </button>
        </div>
        <div phx-click="toggle_sidebar" class="relative m-5 p-2 rounded-md hover:bg-secondary cursor-pointer">
          <div class="absolute right-[10px] top-[8px] w-[8px] h-[8px] rounded-full bg-blue-800" />
          <.icon name="hero-bell" class="h-15 w-15" />
        </div>
      </div>
      <div class="flex flex-col mx-auto max-w-[1280px]">
        <%!-- Welcome section --%>
        <div>
          <.live_component id="welcome" module={Welcome} />
        </div>
        <%!-- Divider --%>
        <div class="border-t-2 border-dashed border-secondary" />
        <%!-- Resources, Nodes and Services  --%>
        <div class="flex flex-col md:flex-row w-full">
          <div class="flex-1"><.live_component id="resources" module={Resources} /></div>
          <div class="flex-1">
            <.live_component id="nodes" module={Nodes} />
            <.live_component id="services" module={Services} />
          </div>
        </div>
        <%!-- Divider --%>
        <div class="border-t-2 border-dashed border-secondary" />
        <%!-- Devices --%>
        <div class="min-h-[200px]">
          <.live_component id="devices" module={Devices} />
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
    <div class="sticky top-0 w-[50px] bg-secondary flex flex-col justify-between p-3">
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

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
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

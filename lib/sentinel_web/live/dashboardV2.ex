defmodule SentinelWeb.Live.DashboardV2 do
  @moduledoc """
  Dashboard V2 Page
  """
  use SentinelWeb, :live_view
  alias SentinelWeb.Live.Components.Sidebar.Details, as: SidebarDetails
  alias Sentinel.Servers.{ Session }
  alias SentinelWeb.Router.Helpers, as: Routes
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
  def mount(_params, %{"ip" => ip} = _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "notifications")
    end

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(
        sidebar: %{
          is_open: false,
          view: :system_overview
        }
      )

    {:ok, socket}
  end

  @doc """
  Render the dashboard.
  """
  def render(assigns) do
    ~H"""
    <div class="relative flex flex-row flex-1 h-screen text-white bg-primary">
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
    <div class="sticky inset-0 w-[30%] max-w-[600px] hidden lg:block rounded-lg system-scroll bg-secondary">
      <div class="h-full">
        <.live_component id="sidebar_details_desktop" module={SidebarDetails} view={@sidebar.view} />
      </div>
    </div>
    <!-- Right panel for small screens when toggled -->
    <div :if={@sidebar.is_open} class="fixed inset-0 bg-secondary lg:hidden z-10 system-scroll">
      <div class="p-4 h-full">
        <!-- Toggle button for small screens only -->
        <button phx-click="close_details" class="lg:hiddeny p-2 m-2">
          Close
        </button>
        <.live_component id="sidebar_details_mobile" module={SidebarDetails} view={@sidebar.view} />
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
    <div class="flex-1 flex flex-col p-5 system-scroll">
      <div class="flex flex-row h-[30px]">
        <div class="flex-1" />
        <div
            phx-click="show_details"
            phx-value-type="overview"
            phx-value-id="_"
          class="relative rounded-md hover:bg-secondary cursor-pointer"
        >
          <div class="absolute right-0 top-0 w-[8px] h-[8px] rounded-full bg-blue-800" />
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
        <div class="flex flex-col md:flex-row w-full gap-6">
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

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  Render Sidebar content
  """
  def handle_event("show_details", %{ "id" => id, "type" => type}, socket) do
    # we need to check the types where we want to request data from
    # Here we tell the GenServers to do the work
    # The broadcast here will be to the component:sidebar - we will render accordingly and replace data
    view = case type do
      "node" ->
        :node
      "service" ->
        Sentinel.Servers.Services.get_service_logs(id)
        :service
      "device" ->
        Sentinel.Servers.Logs.get_device_logs(id)
        :device
      "blacklist" ->
        Sentinel.Servers.Blacklist.init_state()
        :blacklist
      "logs" ->
        Sentinel.Servers.Logs.init_state()
        :logs
      _ ->
        :system_overview
    end

    sidebar = %{
      is_open: true,
      view: view
    }

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  #
  # Close the details bar (relevant when we are in mobile mode)
  #
  def handle_event("close_details", _, socket) do
    sidebar = %{
      is_open: false,
      view: Map.get(socket.assigns.sidebar, :view)
    }

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  #
  # Log out of the sentinel dashboard
  #
  def handle_event("logout", _, socket) do
    # TODO: we need to consider doing a modal over here
    Session.delete(socket.assigns.ip)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
  end

  #
  # ---- handle component updated message :: Client Side Interaction ----
  #

  @spec handle_info(%{ id: String.t(), module: atom(), data: map()}, Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  This will have the parent dashboard view be responsible for sending update messages to components
  """
  def handle_info(%{id: id, module: module, data: data}, socket) do
    send_update(module, id: id, data: data)
    {:noreply, socket}
  end

  #
  # Handle recieving a notification event to show the notification popup
  #
  def handle_info(%{ type: type, message: message}, socket) do
    type = if type in [:info, :error] do
      type
    else
      :info
    end
    IO.inspect("GOT MESSAGE")
    {:noreply, socket |> put_flash(type, message)}
  end
end

defmodule SentinelWeb.Live.Dashboard do
  @moduledoc """
  Dashboard V2 Page
  """
  use SentinelWeb, :live_view
  alias SentinelWeb.Live.Components.Sidebar.Details, as: SidebarDetails
  alias Sentinel.Servers.{Session}
  alias SentinelWeb.Router.Helpers, as: Routes

  alias SentinelWeb.Live.Components.{
    Welcome,
    Resources,
    Services,
    Nodes,
    Devices,
    Modal
  }

  # auth check if this page needs to be behind auth
  on_mount SentinelWeb.Hooks.CheckAuth

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @doc """
  Initialize the dashboard with sidebar set to false.
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "notifications")
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "modal:form:action")
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "status:internet")
    end

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(
        modal: %{
          show: false,
          title: nil,
          body: %{},
          actions: nil
        }
      )
      |> assign(
        sidebar: %{
          is_open: false,
          view: :system_overview
        }
      )
      |> assign(
        status: %{
          internet: false
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
      <!-- Flexible middle column -->
      <%= main(assigns) %>
      <!-- Sidebar for more details -->
      <%= sidebar(assigns) %>
      <%!-- Modal to render confirmations and show data --%>
      <.live_component
        :if={@modal.show}
        module={Modal}
        id="generic_modal"
        title={@modal.title}
        body={@modal.body}
        actions={@modal.actions}
      />
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
    <div class="sticky inset-0 w-[30%] max-w-[600px] hidden lg:block rounded-lg system-scroll bg-secondary m-2">
      <div class="h-full">
        <.live_component id="sidebar_details_desktop" module={SidebarDetails} view={@sidebar.view} />
      </div>
    </div>
    <!-- Right panel for small screens when toggled -->
    <div :if={@sidebar.is_open} class="fixed inset-0 bg-secondary lg:hidden z-1 system-scroll">
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
        <!-- Fixed width left column -->
        <%= nav(assigns) %>

        <div class="flex-1" />

        <div class="flex flex-row gap-2">
          <%!-- Internet Access Placeholder --%>
          <div
            phx-click="show_details"
            phx-value-type="wlan"
            phx-value-id="_"
            class={"#{if @status.internet, do: "bg-green", else: "bg-red"} flex flex-row gap-3 py-2 px-3 items-center rounded-md cursor-pointer"}
          >
            <%!-- We need to use icon here --%> Internet Access
          </div>

          <%!-- VPN Placeholder --%>
          <div
            phx-click="show_details"
            phx-value-type="_"
            phx-value-id="_"
            class="bg-secondary flex flex-row gap-3 py-2 px-3 items-center rounded-md cursor-pointer"
          >
            <%!-- We need to use icon here --%> VPN
          </div>

          <div
            phx-click="show_details"
            phx-value-type="overview"
            phx-value-id="_"
            class="relative rounded-md hover:bg-secondary cursor-pointer"
          >
            <div class="absolute right-0 top-0 w-[10px] h-[10px] rounded-full bg-yellow" />
            <.icon name="hero-bell" class="h-15 w-15" />
          </div>
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
    <div phx-click="logout" class="flex items-center justify-center cursor-pointer">
      <.icon class="w-6 text-gray-2" name="hero-arrow-left-start-on-rectangle" />
    </div>
    """
  end

  #
  # ---- Events :: Client Side Interaction ----
  #
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  Render Sidebar content
  """
  def handle_event("show_details", %{"id" => id, "type" => type}, socket) do
    # we need to check the types where we want to request data from
    # Here we tell the GenServers to do the work
    # The broadcast here will be to the component:sidebar - we will render accordingly and replace data
    view =
      case type do
        "node" ->
          Sentinel.Servers.Nodes.get_node(id)
          :node

        "service" ->
          Sentinel.Servers.Services.get_service_logs(id)
          :service

        "device" ->
          Sentinel.Servers.Logs.get_device_logs(id)
          :device

        "logs" ->
          Sentinel.Servers.Logs.init_state()
          :logs

        "wlan" ->
          Sentinel.Servers.Wlan.scan_networks()
          :wlan

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
    Session.delete(socket.assigns.ip)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
  end

  #
  # Open the modal
  #
  def handle_event("modal_open", params, socket) do
    actions = if params["modal_actions"], do: Jason.decode!(params["modal_actions"]), else: nil

    modal_data = %{
      show: true,
      title: params["modal_title"] || nil,
      body: Jason.decode!(params["modal_body"]) || %{},
      actions: actions
    }

    {:noreply, assign(socket, :modal, modal_data)}
  end

  #
  # Trigger actions
  #
  def handle_event("trigger_action", params, socket) do
    action = params["action"]
    data = Jason.decode!(params["data"])

    send(self(), %{action: action, data: data})
    {:noreply, socket}
  end

  #
  # Close the modal
  #
  def handle_event("modal_close", _params, socket) do
    {:noreply, assign(socket, modal: %{show: false, title: nil, body: %{}, actions: nil})}
  end

  #
  # ---- handle component updated message :: Client Side Interaction ----
  #
  @spec handle_info(%{id: String.t(), module: atom(), data: map()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  This will have the parent dashboard view be responsible for sending update messages to components
  """
  def handle_info(%{id: id, module: module, data: data}, socket) do
    send_update(module, id: id, data: data)
    {:noreply, socket}
  end

  #
  # Handle recieving event for internet status changes
  #
  def handle_info(%{type: :internet, status: status}, socket) do
    socket =
      socket
      |> assign(
        status: %{
          internet: status
        }
      )

    {:noreply, socket}
  end

  #
  # Handle recieving a notification event to show the notification popup
  #
  def handle_info(%{type: type, message: message}, socket) do
    type = if type in [:info, :error], do: type, else: :info
    # Set the flash message
    socket = put_flash(socket, type, message)
    # Schedule flash removal after 3 seconds (3000 ms)
    Process.send_after(self(), :clear_flash, 3000)
    {:noreply, socket}
  end

  #
  # handle the actions from the schema form
  #
  def handle_info(%{action: action, data: data}, socket) do
    case action do
      #
      # Deleting the auto log generated backup
      #

      "backup_file_delete" ->
        decoded_data = Jason.decode!(data)
        Sentinel.Servers.Logs.delete_log_file(decoded_data["file"])

      #
      # Wireless networking
      #
      "connect_to_wireless_network" ->
        Sentinel.Servers.Wlan.connect_with_pass(data["ssid"], data["password"])

      "disconnect_from_wireless_network" ->
        Sentinel.Servers.Wlan.disconnect()
        Process.send_after(self(), :delayed_scan, 3000)

      "scan_for_wireless_networks" ->
        Sentinel.Servers.Wlan.scan_networks()

      #
      # Cloudflare
      #
      "connect_cloudflare" ->
        IO.inspect(data, label: "TODO: __CONNECT_CLOUDFLARE__")

      #
      # Nodes
      #
      "add_node" ->
        Sentinel.Servers.Nodes.add_node(data)

      "remove_node" ->
        %{"id" => id} = Jason.decode!(data)
        Sentinel.Servers.Nodes.remove_node(id)

      _ ->
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :error,
          message: "Action doesnt exist and cant be handled"
        })
    end

    {:noreply, assign(socket, modal: %{show: false, title: nil, body: %{}, actions: nil})}
  end

  #
  # Handle clearing the flash after the delay
  #
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  #
  # handle delayed scan for wireless networks
  #
  def handle_info(:delayed_scan, socket) do
    IO.inspect("Staring delayed scan for wireless networks")
    Sentinel.Servers.Wlan.scan_networks()
    {:noreply, socket}
  end
end

defmodule SentinelWeb.Live.Dashboard do
  @moduledoc """
  Dashboard V2 Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session}
  alias SentinelWeb.Router.Helpers, as: Routes

  # Components
  alias SentinelWeb.Live.Components.Sidebar.Details, as: SidebarDetails
  alias SentinelWeb.Live.Components.Welcome
  alias SentinelWeb.Live.Components.Resources
  alias SentinelWeb.Live.Components.Services
  alias SentinelWeb.Live.Components.Artifacts
  alias SentinelWeb.Live.Components.Devices
  alias SentinelWeb.Live.Components.Modal

  # auth check if this page needs to be behind auth
  on_mount SentinelWeb.Hooks.CheckAuth

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @doc """
  Initialize the dashboard with sidebar set to false.
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "notifications")
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "show_details")
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
          actions: nil,
          type: :default
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
      |> assign(
        settings: %{
          notifications: Sentinel.Servers.Notification.fetch_settings(),
          encryption_key: Sentinel.Servers.Encryption.fetch_settings()
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
        :if={@modal.show && @modal.type === :default}
        module={Modal}
        id="generic_modal"
        title={@modal.title}
        body={@modal.body}
        actions={@modal.actions}
      />

      <%!-- Modal to render confirmations and show data --%>
      <.live_component
        :if={@modal.show && @modal.type === :terminal_session}
        module={Modal}
        id="generic_modal"
        title={@modal.title}
        body={@modal.body}
        actions={@modal.actions}
        type={:terminal_session}
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
      <%!-- Hooks to mount on startup --%>
      <div id="clipboard-hook" phx-hook="CopyToClipboard"></div>

      <div class="flex flex-row h-[30px]">
        <!-- Fixed width left column -->
        <%= nav(assigns) %>

        <div class="flex-1" />

        <div class="flex flex-row gap-1">
          <%!-- Internet Access Placeholder --%>
          <div
            phx-click="show_details"
            phx-value-type="wlan"
            phx-value-id="_"
            class={"#{if @status.internet, do: "bg-green", else: "bg-red"} flex flex-row gap-3 py-2 px-3 items-center rounded-md cursor-pointer"}
          >
            <%!-- We need to use icon here --%> Internet Access
          </div>

          <%!-- General Settings --%>
          <div
            phx-click="modal_open"
            phx-value-modal_title="Notification Settings"
            phx-value-modal_body={
              Jason.encode!(%{
                "type" => "schema",
                "data" => Sentinel.Schema.Settings.data(:notifications),
                "default_values" => @settings.notifications,
                "action" => "update_notifications"
              })
            }
            class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md text-gray-1"
          >
            <.icon name="hero-cog-6-tooth" class="h-15 w-15" />
          </div>

          <div
            phx-click="modal_open"
            phx-value-modal_title="Encryption Settings"
            phx-value-modal_body={
              Jason.encode!(%{
                "type" => "schema",
                "data" => Sentinel.Schema.Settings.data(:encryption),
                "default_values" => %{
                  "encryption_key" => @settings.encryption_key
                },
                "action" => "copy_encryption_key",
                "title" => "Copy"
              })
            }
            class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md text-gray-1"
          >
            <.icon name="hero-key" class="h-15 w-15" />
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
        <%!-- Resources, Artifacts and Services  --%>
        <div class="flex flex-col md:flex-row w-full gap-6">
          <div class="flex-1"><.live_component id="resources" module={Resources} /></div>
          <div class="flex-1">
            <.live_component id="services" module={Services} />
          </div>
        </div>
        <%!-- Divider --%>
        <div class="border-t-2 border-dashed border-secondary" />

        <%!-- Artifacts --%>
        <div class="min-h-[200px]">
          <.live_component id="artifacts" module={Artifacts} />
        </div>

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
    sidebar = %{
      is_open: true,
      view: get_sidebar_details(type, id)
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
      actions: actions,
      type: :default
    }

    # We make sure when opening the modal, we are updating the fields we need based on type
    {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal_data))}
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
    modal_data = %{show: false, title: nil, body: %{}, actions: nil, type: :default}

    {:noreply, assign(socket, :modal, modal_data)}
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
    # Process.send_after(self(), :clear_flash, 3000)
    {:noreply, socket}
  end

  #
  # handle the actions from the schema form
  #
  def handle_info(%{action: action, data: data}, socket) do
    case action do
      #
      # Wireless networking
      #
      "connect_to_wireless_network" ->
        Sentinel.Servers.Wlan.connect_with_pass(data["ssid"], data["password"])

      "disconnect_from_wireless_network" ->
        Sentinel.Servers.Wlan.disconnect()
        Process.send_after(self(), :delayed_scan, 3000)

      "scan_for_wireless_networks" ->
        send(self(), :scan_for_wireless_networks)

      #
      # Cloudflare
      #
      "connect_cloudflare" ->
        Sentinel.Servers.Cloudflare.add_host(data["service"], data["domain"])

      "disconnect_cloudflare" ->
        %{"subdomain" => subdomain} = Jason.decode!(data)
        Sentinel.Servers.Cloudflare.remove_host(subdomain)

      #
      # Artifacts
      #
      "add_artifact" ->
        Sentinel.Servers.Artifacts.add_artifact(data)

      #
      # Notification Settings
      #
      "update_notifications" ->
        resp = Sentinel.Servers.Notification.update_settings(data)
        send(self(), {:update_notification_settings, resp})

      #
      # Encryption Settings
      #
      "copy_encryption_key" ->
        %{"encryption_key" => key} = data
        send(self(), {:copy_encyption_key, key})

      "remove_artifact" ->
        %{"id" => id, "subdomain" => subdomain} = Jason.decode!(data)
        Sentinel.Servers.Artifacts.remove_artifact(id)

        if subdomain do
          Sentinel.Servers.Cloudflare.remove_host(subdomain)
        end

      "sentinet_settings" ->
        Sentinel.Servers.Artifacts.update_artifact(data, :sentinet)

      #
      # Terminal Session
      # --
      # We trigger a message to the current live view to open a modal for rendering an iframe
      #
      "open_terminal" ->
        send(self(), :terminal_session)

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
  # NOTE: This will be deprecated as we dont need to clear automatically
  # Useful if we keep a timestamp in future to decide accumulated is all shown too
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

  #
  # Copy the encryption key to the client clipboard
  #
  def handle_info({:copy_encyption_key, key}, socket) do
    socket =
      socket
      |> push_event("copy_to_clipboard", %{text: key})
      |> put_flash(:info, "Copied to clipboard!")

    {:noreply, socket}
  end

  #
  # handle terminal session init
  # This assumes ttyd is installed on the device
  #
  def handle_info(:terminal_session, socket) do
    modal_data = %{
      show: true,
      title: "Terminal Session",
      body: %{
        "ip" => Application.get_env(:sentinel, :network)[:gateway],
        "port" => Application.get_env(:sentinel, :ttyd)[:port]
      },
      type: :terminal_session
    }

    {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal_data))}
  end

  #
  # Handle the success case of updating notification settings
  # We update the state for the form
  #
  def handle_info({:update_notification_settings, {:ok, data}}, socket) do
    settings = %{
      socket.assigns.settings
      | notifications: data
    }

    {:noreply, assign(socket, :settings, settings)}
  end

  #
  # Background job in order to process the network fetch
  #
  def handle_info(:scan_for_wireless_networks, socket) do
    Task.start(fn -> Sentinel.Servers.Wlan.scan_networks() end)
    {:noreply, put_flash(socket, :info, "Scanning for wireless networks")}
  end

  #
  # Show details - server request
  # NOTE: we have a function to do this client side but this is a listener for the server
  #
  def handle_info({:show_details, %{"id" => id, "type" => type}}, socket) do
    sidebar = %{
      is_open: true,
      view: get_sidebar_details(type, id)
    }

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  #
  # Get the sidebar details that is used for client and server sider trigger render
  #
  defp get_sidebar_details(type, id) do
      case type do
        "artifact" ->
          Sentinel.Servers.Artifacts.get_artifact(id)
          :artifact

        "service" ->
          Sentinel.Servers.Services.get_service_logs(id)
          :service

        "wlan" ->
          Sentinel.Servers.Wlan.scan_networks()
          :wlan

        _ ->
          :system_overview
      end
  end
end

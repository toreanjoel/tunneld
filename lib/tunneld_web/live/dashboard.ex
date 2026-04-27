defmodule TunneldWeb.Live.Dashboard do
  @moduledoc """
  Dashboard V2 Page
  """
  use TunneldWeb, :live_view
  require Logger
  alias Tunneld.Servers.Session
  alias Tunneld.Servers.Devices, as: DevicesServer
  alias TunneldWeb.Router.Helpers, as: Routes

  # Components
  alias TunneldWeb.Live.Components.Sidebar.Details, as: SidebarDetails
  alias TunneldWeb.Live.Components.Welcome
  alias TunneldWeb.Live.Components.SystemResources
  alias TunneldWeb.Live.Components.Services
  alias TunneldWeb.Live.Components.Resources
  alias TunneldWeb.Live.Components.Devices
  alias TunneldWeb.Live.Components.Wireguard.Server, as: WireguardServer
  alias TunneldWeb.Live.Dashboard.Actions

  @modal_default %{
    show: false,
    title: nil,
    description: nil,
    body: %{},
    actions: nil,
    type: :default
  }

  @sidebar_default %{
    is_open: false,
    view: nil,
    selection: nil
  }

  # auth check if this page needs to be behind auth
  on_mount TunneldWeb.Hooks.CheckAuth

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @doc """
  Initialize the dashboard with sidebar set to false.
  """
  def mount(_params, %{"client_id" => client_id} = _session, socket) do
    # Redirect to setup wizard if not yet onboarded
    needs_setup =
      case Tunneld.Servers.Auth.read_file() do
        {:ok, auth} -> not Map.get(auth, "onboarded", false)
        _ -> false
      end

    if needs_setup do
      {:ok, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Setup))}
    else
      mount_dashboard(client_id, socket)
    end
  end

  defp mount_dashboard(client_id, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "notifications")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "show_details")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "modal:form:action:#{client_id}")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "status:internet")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:devices")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:wireguard")
    end

    # Check the scheme and domain to make sure it is possible to show
    uri_info = get_connect_info(socket, :uri)
    devices = DevicesServer.fetch_devices()

    internet_status =
      try do
        Tunneld.Servers.Wlan.connected?()
      rescue
        _ -> false
      end

    socket =
      socket
      |> assign(:client_id, client_id)
      |> assign(:uri_info, uri_info)
      |> assign(modal: @modal_default)
      |> assign(sidebar: @sidebar_default)
      |> assign(
        status: %{
          internet: internet_status
        }
      )
      |> assign(:devices, devices)
      |> assign(:pending_actions, %{})
      |> assign(:wireguard_state, wireguard_state())
      |> assign(:settings_menu_open, false)
      |> assign(:obfuscated, false)

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

      <%= if @sidebar.is_open do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 z-2" phx-click="close_details" />
      <% end %>
      <!-- Sidebar for more details -->
      <%= if not is_nil(@sidebar.view), do: sidebar(assigns) %>

      <.live_component
        :if={@modal.show && @modal.type === :default}
        module={TunneldWeb.Live.Components.Modal}
        id="generic_modal"
        title={@modal.title}
        description={@modal.description}
        body={@modal.body}
        actions={@modal.actions}
        client_id={@client_id}
        pending_actions={@pending_actions}
      />
    </div>
    """
  end

  @spec sidebar(%{
          :sidebar => %{is_open: boolean(), view: atom(), selection: map() | nil},
          optional(any()) => any()
        }) ::
          Phoenix.LiveView.Rendered.t()
  @doc """
  Overlay sidebar with close button and responsive width.
  """
  def sidebar(%{sidebar: sidebar, uri_info: uri_info} = assigns) do
    assigns =
      assigns
      |> assign(:sidebar, sidebar)
      |> assign(:uri_info, uri_info)

    ~H"""
    <div
      :if={@sidebar.is_open}
      class="fixed top-0 right-0 z-19 h-screen w-screen lg:w-[35%] lg:max-w-[700px] bg-secondary system-scroll shadow-lg transition-transform duration-300 ease-in-out"
    >
      <button
        phx-click="close_details"
        class="absolute top-4 right-5 z-10"
      >
        <.icon class="w-5 h-5" name="hero-x-mark" />
      </button>

      <div class="h-full pt-12 overflow-y-auto">
        <.live_component
          id="sidebar_details"
          module={SidebarDetails}
          view={@sidebar.view}
          uri_info={@uri_info}
          selection={@sidebar.selection}
          obfuscated={@obfuscated}
        />
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
    <div class="flex-1 flex flex-col p-3 md:p-5 system-scroll">
      <div class="flex flex-row items-center gap-2">
        <!-- Logout -->
        <%= nav(assigns) %>

        <div class="flex-1" />

        <div class="flex flex-row flex-wrap justify-end gap-1">
          <%!-- Private Network Access --%>
          <div
            phx-click="show_details"
            phx-value-type="zrok"
            phx-value-id="_"
            class="bg-purple flex flex-row gap-2 py-2 px-2 md:px-3 items-center rounded-md cursor-pointer text-white text-xs font-medium hover:opacity-80 transition-all"
          >
            <.icon name="hero-signal" class="h-4 w-4" />
            <span class="hidden sm:inline">Configure Network</span>
          </div>

          <%!-- Internet Access --%>
          <div
            phx-click="show_details"
            phx-value-type="wlan"
            phx-value-id="_"
            class={"#{if @status.internet, do: "bg-green", else: "bg-red"} flex flex-row gap-2 py-2 px-2 md:px-3 items-center rounded-md cursor-pointer text-white text-xs font-medium hover:opacity-80 transition-all"}
          >
            <.icon name="hero-wifi" class="h-4 w-4" />
            <span class="hidden sm:inline">Internet Access</span>
          </div>

          <%!-- Obfuscation Toggle --%>
          <div
            id="obfuscation-toggle"
            phx-hook="ObfuscationToggle"
            class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md text-gray-1 hover:opacity-80 transition-all"
            title={if @obfuscated, do: "Show sensitive data", else: "Hide sensitive data"}
          >
            <.icon
              name={if @obfuscated, do: "hero-eye-slash", else: "hero-eye"}
              class="h-4 w-4"
            />
          </div>

          <%!-- Settings Menu --%>
          <div class="relative">
            <div
              phx-click="toggle_settings_menu"
              class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md text-gray-1 hover:opacity-80 transition-all"
            >
              <.icon name="hero-cog-6-tooth" class="h-4 w-4" />
            </div>

            <div
              :if={@settings_menu_open}
              phx-click-away="close_settings_menu"
              class="absolute right-0 top-full mt-1 w-48 bg-secondary rounded-md shadow-lg z-10 py-1 border border-gray-700"
            >
              <div
                phx-click="open_settings"
                phx-value-type="authentication"
                class="flex items-center gap-2 px-3 py-2 text-xs text-gray-1 hover:bg-primary cursor-pointer transition-all"
              >
                <.icon name="hero-lock-closed" class="h-4 w-4" /> Authentication
              </div>
              <div class="border-t border-gray-700 my-1" />
              <div
                phx-click="restart_device"
                class="flex items-center gap-2 px-3 py-2 text-xs text-red hover:bg-primary cursor-pointer transition-all"
              >
                <.icon name="hero-arrow-path" class="h-4 w-4" /> Restart Device
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-col mx-auto max-w-[1280px] w-full">
        <%!-- Welcome section --%>
        <div>
          <.live_component id="welcome" module={Welcome} />
        </div>
        <%!-- Divider --%>
        <div class="border-t-2 border-dashed border-secondary" />
        <%!-- System Resources, Services, and VPN --%>
        <div class="flex flex-col md:flex-row w-full gap-2">
          <div class="flex-1"><.live_component id="system_resources" module={SystemResources} /></div>
          <div class="flex-1 flex flex-col gap-4">
            <.live_component id="services" module={Services} obfuscated={@obfuscated} />
            <.live_component id="wireguard_server" module={WireguardServer} data={@wireguard_state} obfuscated={@obfuscated} />
          </div>
        </div>

        <%!-- Divider --%>
        <div class="border-t-2 border-dashed border-secondary" />

        <%!-- Resources and Devices --%>
        <div class="mt-4 md:mt-6">
          <div class="min-h-[150px] md:min-h-[200px]">
            <.live_component id="resources" module={Resources} obfuscated={@obfuscated} />
          </div>

          <div class="min-h-[150px] md:min-h-[200px]">
            <.live_component id="devices" module={Devices} obfuscated={@obfuscated} />
          </div>
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

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  Render Sidebar content
  """
  def handle_event("restart_device", _params, socket) do
    modal_data = modal_open(%{
      title: "Restart Device?",
      description: "This will restart the gateway service. The dashboard will be temporarily unavailable.",
      body: %{
        "type" => "string",
        "data" => "All active connections will be interrupted. The device will come back online automatically."
      },
      actions: %{
        "title" => "Restart",
        "payload" => %{
          "type" => "restart_device",
          "data" => %{}
        }
      }
    })

    {:noreply, socket |> assign(:modal, modal_data) |> assign(:settings_menu_open, false)}
  end

  def handle_event("toggle_obfuscation", %{"obfuscated" => obfuscated}, socket) do
    obfuscated = obfuscated in ["true", true]
    {:noreply, assign(socket, :obfuscated, obfuscated)}
  end

  def handle_event("toggle_settings_menu", _params, socket) do
    {:noreply, assign(socket, :settings_menu_open, !socket.assigns.settings_menu_open)}
  end

  def handle_event("close_settings_menu", _params, socket) do
    {:noreply, assign(socket, :settings_menu_open, false)}
  end

  def handle_event("open_settings", %{"type" => type}, socket) do
    sidebar = sidebar_open(get_sidebar_details(type, "_"), sidebar_selection(type, "_"))

    {:noreply, socket |> assign(:sidebar, sidebar) |> assign(:settings_menu_open, false)}
  end

  def handle_event("show_details", %{"id" => id, "type" => type}, socket) do
    sidebar = sidebar_open(get_sidebar_details(type, id), sidebar_selection(type, id))

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  #
  # Catch the toggle event to enable/disable the resources and their resources
  #
  def handle_event("toggle_share_access", params, socket) do
    {:noreply, start_action("toggle_share_access", params, socket)}
  end

  def handle_event("toggle_vpn", %{"enabled" => "true"}, socket) do
    {:noreply, start_action("enable_wireguard", %{}, socket)}
  end

  def handle_event("toggle_vpn", %{"enabled" => "false"}, socket) do
    {:noreply, start_action("disable_wireguard", %{}, socket)}
  end

  def handle_event("revoke_wireguard_peer", %{"peer_id" => peer_id, "peer_name" => _name}, socket) do
    {:noreply, start_action("remove_wireguard_peer", %{"peer_id" => peer_id}, socket)}
  end

  def handle_event("show_peer_config", %{"peer_id" => peer_id, "peer_name" => name}, socket) do
    config = Tunneld.Servers.Wireguard.get_peer_config(peer_id)

    if config do
      filename = "#{name}.conf"
      sidebar = %{
        is_open: true,
        view: :wireguard_peer_config,
        selection: %{config_text: config, filename: filename, peer_name: name}
      }
      {:noreply, assign(socket, :sidebar, sidebar)}
    else
      {:noreply, put_flash(socket, :info, "Config not cached. Regenerate the peer config to view QR code.")}
    end
  end

  #
  # Close the details bar (relevant when we are in mobile mode)
  #
  def handle_event("close_details", _, socket) do
    sidebar = sidebar_close(socket.assigns.sidebar)

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  #
  # Log out of the tunneld dashboard
  #
  def handle_event("logout", _, socket) do
    Session.delete(socket.assigns.client_id)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, TunneldWeb.Live.Login))}
  end

  #
  # Trigger actions
  #
  def handle_event("trigger_action", params, socket) do
    action = params["action"]
    data = Jason.decode!(params["data"])

    {:noreply, start_action(action, data, socket)}
  end

  #
  # Open the modal
  #
  def handle_event("modal_open", params, socket) do
    actions = if params["modal_actions"], do: Jason.decode!(params["modal_actions"]), else: nil

    modal_data = %{
      show: true,
      title: params["modal_title"] || nil,
      description: params["modal_description"] || nil,
      body: Jason.decode!(params["modal_body"]) || %{},
      actions: actions,
      type: :default
    }

    # We make sure when opening the modal, we are updating the fields we need based on type
    {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal_data))}
  end

  #
  # Close the modal
  #
  def handle_event("modal_close", _params, socket) do
    {:noreply, assign(socket, :modal, @modal_default)}
  end

  @spec handle_info(%{id: String.t(), module: atom(), data: map()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  This will have the parent dashboard view be responsible for sending update messages to components
  """
  def handle_info(
        %{id: "devices", module: TunneldWeb.Live.Components.Devices, data: data} = message,
        socket
      ) do
    send_update(message.module, id: message.id, data: message.data, obfuscated: socket.assigns.obfuscated)

    devices = Map.get(data, :devices, [])

    {:noreply, assign(socket, :devices, devices)}
  end

  def handle_info(
        %{id: "resources", module: TunneldWeb.Live.Components.Resources, data: data} = message,
        socket
      ) do
    send_update(message.module, id: message.id, data: message.data, obfuscated: socket.assigns.obfuscated)

    socket =
      socket
      |> maybe_refresh_sidebar_details(data)

    {:noreply, socket}
  end

  def handle_info(%{id: "wireguard_" <> _, module: _module, data: wg_data}, socket) do
    socket =
      socket
      |> assign(:wireguard_state, wg_data)
      |> maybe_refresh_wireguard_sidebar()

    {:noreply, socket}
  end

  def handle_info(%{id: id, module: module, data: data}, socket) do
    if not is_nil(id) do
      send_update(module, id: id, data: data, obfuscated: socket.assigns.obfuscated)
    end

    {:noreply, socket}
  end

  #
  # Handle recieving event for internet status changes
  #
  def handle_info(%{type: :internet, status: status}, socket) do
    socket =
      socket
      |> assign(status: %{internet: status})

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
    {:noreply, start_action(action, data, socket)}
  end

  #
  # Handle the completion of an async action
  #
  def handle_info({:action_done, ref, _action, {:error, reason}}, socket) do
    pending = Map.get(socket.assigns.pending_actions, ref, %{})
    Logger.error("Action failed: #{inspect(reason)}")

    socket =
      socket
      |> assign(:pending_actions, Map.delete(socket.assigns.pending_actions, ref))
      |> maybe_keep_modal_open(pending)
      |> put_flash(:error, "Action failed, please retry.")

    {:noreply, socket}
  end

  def handle_info({:action_done, ref, "add_wireguard_peer", {:ok, {:ok, peer, config}}}, socket) do
    filename = "#{peer["name"]}.conf"
    sidebar = %{
      is_open: true,
      view: :wireguard_peer_config,
      selection: %{config_text: config, filename: filename, peer_name: peer["name"]}
    }

    socket =
      socket
      |> assign(:pending_actions, Map.delete(socket.assigns.pending_actions, ref))
      |> assign(:sidebar, sidebar)
      |> assign(:modal, @modal_default)

    {:noreply, socket}
  end

  def handle_info({:action_done, ref, "remove_wireguard_peer", {:ok, _result}}, socket) do
    socket =
      socket
      |> assign(:pending_actions, Map.delete(socket.assigns.pending_actions, ref))
      |> put_flash(:info, "VPN peer removed")

    {:noreply, socket}
  end

  def handle_info({:action_done, ref, action, _result}, socket)
      when action in ["add_device_tag", "remove_device_tag"] do
    pending = Map.get(socket.assigns.pending_actions, ref, %{})
    devices = DevicesServer.fetch_devices()

    send_update(Devices, id: "devices", data: %{count: length(devices), devices: devices})

    socket =
      socket
      |> assign(:pending_actions, Map.delete(socket.assigns.pending_actions, ref))
      |> assign(:devices, devices)
      |> maybe_close_modal_after_success(pending)

    {:noreply, socket}
  end

  def handle_info({:action_done, ref, _action, _result}, socket) do
    pending = Map.get(socket.assigns.pending_actions, ref, %{})

    socket =
      socket
      |> assign(:pending_actions, Map.delete(socket.assigns.pending_actions, ref))
      |> maybe_close_modal_after_success(pending)

    {:noreply, socket}
  end

  #
  # handle delayed scan for wireless networks
  #
  def handle_info(:delayed_scan, socket) do
    Tunneld.Servers.Wlan.scan_networks()
    {:noreply, socket}
  end

  #
  # Background job in order to process the network fetch
  #
  def handle_info(:scan_for_wireless_networks, socket) do
    Task.start(fn -> Tunneld.Servers.Wlan.scan_networks() end)
    {:noreply, put_flash(socket, :info, "Scanning for wireless networks")}
  end

  #
  # Revoke the login credentials
  #
  def handle_info(:revoke_login_creds, socket) do
    {:noreply,
     put_flash(socket, :info, "Auth reset. Next login will require a new password to be setup")}
  end

  def handle_info(:close_details, socket) do
    {:noreply, assign(socket, :sidebar, sidebar_close(socket.assigns.sidebar))}
  end

  def handle_info({:show_details, %{"id" => id, "type" => type}}, socket) do
    sidebar = sidebar_open(get_sidebar_details(type, id), sidebar_selection(type, id))

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  #
  # Get the sidebar details that is used for client and server sider trigger render
  #
  defp get_sidebar_details(type, id) do
    case type do
      "resource" ->
        Tunneld.Servers.Resources.get_resource(id)
        :resource

      "service" ->
        Tunneld.Servers.Services.get_service_logs(id)
        :service

      "wlan" ->
        Tunneld.Servers.Wlan.scan_networks()
        :wlan

      "blocklist" ->
        Tunneld.Servers.Blocklist.get_details()
        :blocklist

      "zrok" ->
        # Get the current state so we can prepopulate
        Tunneld.Servers.Zrok.get_details()
        :zrok

      "authentication" ->
        :authentication

      "wireguard" ->
        if _pid = GenServer.whereis(Tunneld.Servers.Wireguard) do
          Tunneld.Servers.Wireguard.get_state()
        else
          %{"enabled" => false, "peers" => %{}}
        end
        :wireguard
    end
  end

  defp sidebar_selection("resource", id) when is_binary(id), do: %{type: :resource, id: id}
  defp sidebar_selection(_, _), do: nil

  defp maybe_refresh_sidebar_details(socket, resources) do
    sidebar = Map.get(socket.assigns, :sidebar, %{})
    resources = List.wrap(resources)

    with true <- Map.get(sidebar, :is_open, false),
         :resource <- Map.get(sidebar, :view),
         %{type: :resource, id: selected_id} <- Map.get(sidebar, :selection),
         %{} = resource <- Enum.find(resources, &resource_match?(&1, selected_id)) do
      send_update(SidebarDetails, id: "sidebar_details", data: resource)
    end

    socket
  end

  defp resource_match?(resource, id) do
    res_id = Map.get(resource, :id) || Map.get(resource, "id")
    res_id == id
  end

  #
  # Wrap actions in an async task to prevent UI hangs while tracking pending state
  #
  defp start_action(action, data, socket) do
    action_ref = System.unique_integer([:positive, :monotonic])
    parent = self()
    schema_modal? = modal_is_schema?(socket)

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: :info,
      message: start_message(action)
    })

    Task.start(fn ->
      result =
        try do
          {:ok, Actions.perform(action, data, parent)}
        rescue
          e -> {:error, e}
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      send(parent, {:action_done, action_ref, action, result})
    end)

    socket =
      socket
      |> assign(
        :pending_actions,
        Map.put(socket.assigns.pending_actions, action_ref, %{
          action: action,
          keep_modal_open: schema_modal?
        })
      )

    if schema_modal? do
      socket
    else
      reset_modal(socket)
    end
  end

  defp reset_modal(socket) do
    assign(socket, :modal, @modal_default)
  end

  defp modal_is_schema?(socket), do: modal_schema_form?(socket.assigns)

  defp maybe_keep_modal_open(socket, %{keep_modal_open: true}) do
    modal = Map.get(socket.assigns, :modal, %{}) |> Map.put(:show, true)
    assign(socket, :modal, modal)
  end

  defp maybe_keep_modal_open(socket, _), do: socket

  defp maybe_close_modal_after_success(socket, %{keep_modal_open: true}), do: reset_modal(socket)
  defp maybe_close_modal_after_success(socket, _), do: socket

  # Human friendly messages for pending actions
  defp start_message(action) do
    case action do
      "add_share" -> "Adding resource..."
      "add_private_share" -> "Binding private resource..."
      "remove_share" -> "Removing resource..."
      "toggle_share_access" -> "Updating resource access..."
      "tunneld_settings" -> "Updating resource settings..."
      "restart_service" -> "Restarting service..."
      "refresh_service_logs" -> "Refreshing service logs..."
      "revoke_release_ip" -> "Releasing device IP..."
      "allow_device_expose" -> "Enabling Quick Expose..."
      "revoke_device_expose" -> "Revoking Quick Expose..."
      "add_device_tag" -> "Adding tag..."
      "remove_device_tag" -> "Removing tag..."
      "connect_to_wireless_network" -> "Connecting to Wi‑Fi..."
      "disconnect_from_wireless_network" -> "Disconnecting Wi‑Fi..."
      "scan_for_wireless_networks" -> "Scanning Wi‑Fi..."
      "configure_enable_control_plane" -> "Configuring control plane..."
      "configure_disable_control_plane" -> "Disconnecting control plane..."
      "configure_enable_environment" -> "Enabling device..."
      "configure_disable_environment" -> "Disabling device..."
      "revoke_login_creds" -> "Resetting login..."
      "update_blocklist" -> "Updating blocklist..."
      "configure_basic_auth" -> "Configuring Basic Auth..."
      "disable_basic_auth" -> "Disabling Basic Auth..."
      "get_private_token" -> "Fetching private token..."
      "add_wireguard_peer" -> "Adding VPN peer..."
      "remove_wireguard_peer" -> "Removing VPN peer..."
      "enable_wireguard" -> "Enabling VPN server..."
      "disable_wireguard" -> "Disabling VPN server..."
      "restart_device" -> "Restarting device..."
      _ -> "Working on request..."
    end
  end

  # --- Modal & Sidebar state helpers ---

  defp modal_open(fields) when is_map(fields) do
    Map.merge(@modal_default, Map.put(fields, :show, true))
  end

  defp modal_schema_form?(socket_assigns) do
    socket_assigns
    |> Map.get(:modal, %{})
    |> Map.get(:body, %{})
    |> case do
      %{"type" => "schema"} -> true
      _ -> false
    end
  end

  defp sidebar_open(view, selection) when is_atom(view) do
    %{is_open: true, view: view, selection: selection}
  end

  defp sidebar_close(sidebar) when is_map(sidebar) do
    %{is_open: false, view: Map.get(sidebar, :view), selection: nil}
  end

  defp wireguard_state do
    if _pid = GenServer.whereis(Tunneld.Servers.Wireguard) do
      Tunneld.Servers.Wireguard.get_state()
    else
      %{"enabled" => false, "peers" => %{}}
    end
  end

  defp maybe_refresh_wireguard_sidebar(socket) do
    sidebar = Map.get(socket.assigns, :sidebar, %{})

    if Map.get(sidebar, :is_open, false) and Map.get(sidebar, :view) == :wireguard do
      assign(socket, :sidebar, %{
        sidebar
        | selection: %{updated_at: System.monotonic_time()}
      })
    else
      socket
    end
  end
end

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
  alias TunneldWeb.Live.Components.Modal
  alias TunneldWeb.Live.Dashboard.{Actions, NetworkGraph}

  # auth check if this page needs to be behind auth
  on_mount TunneldWeb.Hooks.CheckAuth

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @doc """
  Initialize the dashboard with sidebar set to false.
  """
  def mount(_params, %{"client_id" => client_id} = _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "notifications")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "show_details")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "modal:form:action:#{client_id}")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "status:internet")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:devices")
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
      |> assign(:allow_webauthn?, false)
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
          view: nil,
          selection: nil
        }
      )
      |> assign(
        status: %{
          internet: internet_status
        }
      )
      |> assign(:devices, devices)
      |> assign(:view_tab, :list)
      |> assign(:network_graph, NetworkGraph.build(internet_status, devices))
      |> assign(:pending_actions, %{})

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
        module={Modal}
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
          :allow_webauthn? => boolean(),
          :sidebar => %{is_open: boolean(), view: atom(), selection: map() | nil},
          optional(any()) => any()
        }) ::
          Phoenix.LiveView.Rendered.t()
  @doc """
  Overlay sidebar with close button and responsive width.
  """
  def sidebar(%{sidebar: sidebar, allow_webauthn?: allow_webauthn?, uri_info: uri_info} = assigns) do
    assigns =
      assigns
      |> assign(:sidebar, sidebar)
      |> assign(:uri_info, uri_info)
      |> assign(:allow_webauthn?, allow_webauthn?)

    ~H"""
    <div
      :if={@sidebar.is_open}
      class="fixed top-0 right-0 z-19 h-screen w-screen lg:w-[30%] lg:max-w-[600px] bg-secondary system-scroll shadow-lg transition-transform duration-300 ease-in-out"
    >
      <button phx-click="close_details" class="absolute top-4 right-5">
        <.icon class="w-5 h-5" name="hero-x-mark" />
      </button>

      <div class="h-full">
        <.live_component
          id="sidebar_details"
          module={SidebarDetails}
          view={@sidebar.view}
          uri_info={@uri_info}
          web_authn={@allow_webauthn?}
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
    <div class="flex-1 flex flex-col p-5 system-scroll">
      <%!-- Hooks to mount on startup --%>
      <div id="clipboard-hook" phx-hook="CopyToClipboard"></div>

      <div class="flex flex-row h-[30px]">
        <!-- Fixed width left column -->
        <%= nav(assigns) %>

        <div class="flex-1" />

        <div class="flex flex-row gap-1">
          <%!-- Private Network Access --%>
          <div
            phx-click="show_details"
            phx-value-type="zrok"
            phx-value-id="_"
            class="bg-purple flex flex-row gap-3 py-2 px-3 items-center rounded-md cursor-pointer"
          >
            Configure Network
          </div>

          <%!-- Internet Access --%>
          <div
            phx-click="show_details"
            phx-value-type="wlan"
            phx-value-id="_"
            class={"#{if @status.internet, do: "bg-green", else: "bg-red"} flex flex-row gap-3 py-2 px-3 items-center rounded-md cursor-pointer"}
          >
            Internet Access
          </div>

          <%!-- Auth Settings  --%>
          <div
            phx-click="show_details"
            phx-value-type="authentication"
            phx-value-id="_"
            class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md text-gray-1"
          >
            <.icon name="hero-cog-6-tooth" class="h-15 w-15" />
          </div>
        </div>
      </div>

      <div class="flex flex-col mx-auto max-w-[1280px] w-[980px]">
        <%!-- Welcome section --%>
        <div>
          <.live_component id="welcome" module={Welcome} />
        </div>
        <%!-- Divider --%>
        <div class="border-t-2 border-dashed border-secondary" />
        <%!-- Resources, Resources and Services  --%>
        <div class="flex flex-col md:flex-row w-full gap-6">
          <div class="flex-1"><.live_component id="system_resources" module={SystemResources} /></div>
          <div class="flex-1">
            <.live_component id="services" module={Services} />
          </div>
        </div>
        <%!-- Divider --%>
        <div class="border-t-2 border-dashed border-secondary" />

        <%!-- IMPORTANT SECTION WHERE CHANGES WILL TAKE PLACE  --%>
        <div class="mt-6">
          <div class="flex flex-row items-center gap-2 mb-4">
            <div class="flex flex-row gap-2">
              <button
                phx-click="set_view_tab"
                phx-value-tab="list"
                class={
                  "px-4 py-2 rounded-md text-sm font-semibold border " <>
                    if @view_tab == :list do
                      "bg-secondary border-secondary text-white"
                    else
                      "bg-primary border-secondary text-gray-1"
                    end
                }
              >
                Resource List
              </button>
              <button
                phx-click="set_view_tab"
                phx-value-tab="map"
                class={
                  "px-4 py-2 rounded-md text-sm font-semibold border " <>
                    if @view_tab == :map do
                      "bg-secondary border-secondary text-white"
                    else
                      "bg-primary border-secondary text-gray-1"
                    end
                }
              >
                Network Map
              </button>
            </div>
            <div class="flex-1" />
            <%!-- <button
              :if={@view_tab == :map}
              id="download-network-map" phx-hook="DownloadNetworkMap"
              class="ml-auto px-4 py-2 rounded-md text-sm font-semibold border bg-primary border-secondary text-gray-1 hover:text-white hover:border-white transition"
            >
              Download map
            </button> --%>
          </div>

          <div class={"#{if @view_tab == :map, do: "hidden"}"}>
            <div class="min-h-[200px]">
              <.live_component id="resources" module={Resources} />
            </div>

            <div class="min-h-[200px]">
              <.live_component id="devices" module={Devices} />
            </div>
          </div>

          <div class={"#{if @view_tab == :list, do: "hidden"}"}>
            <div>
              <div
                id="network-map"
                class="network-board"
                phx-hook="NetworkMap"
                data-graph={Jason.encode!(@network_graph)}
              >
                <div class="loader" id="loader">
                  <span>Loading…</span>
                </div>
                <canvas id="iso"></canvas>
              </div>
            </div>
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
  def handle_event("show_details", %{"id" => id, "type" => type}, socket) do
    sidebar = %{
      is_open: true,
      view: get_sidebar_details(type, id),
      selection: sidebar_selection(type, id)
    }

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  def handle_event("set_view_tab", %{"tab" => tab}, socket) do
    view_tab = if tab == "map", do: :map, else: :list

    socket =
      socket
      |> assign(:view_tab, view_tab)
      |> rebuild_network_graph()

    {:noreply, socket}
  end

  #
  # Catch the toggle event to enable/disable the resources and their resources
  #
  def handle_event("toggle_share_access", params, socket) do
    {:noreply, start_action("toggle_share_access", params, socket)}
  end

  #
  # Close the details bar (relevant when we are in mobile mode)
  #
  def handle_event("close_details", _, socket) do
    sidebar = %{
      is_open: false,
      view: Map.get(socket.assigns.sidebar, :view),
      selection: nil
    }

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  #
  # Completed the WebAuthn registration
  #
  def handle_event("webauthn_register_complete", %{} = data, socket) do
    case Tunneld.Servers.Auth.save_webauthn(data) do
      :ok ->
        socket = put_flash(socket, :info, "WebAuthn credential saved successfully")
        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to save WebAuthn credential: #{inspect(reason)}")
        socket = put_flash(socket, :error, "Failed to save WebAuthn credential")
        {:noreply, socket}
    end
  end

  #
  # Error completing the WebAuthn registration
  #
  def handle_event("webauthn_register_error", %{"error" => err}, socket) do
    {:noreply, socket |> put_flash(:error, err)}
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
    modal_data = %{show: false, title: nil, description: nil, body: %{}, actions: nil, type: :default}

    {:noreply, assign(socket, :modal, modal_data)}
  end

  @spec handle_info(%{id: String.t(), module: atom(), data: map()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  This will have the parent dashboard view be responsible for sending update messages to components
  """
  def handle_info(%{id: "devices", module: TunneldWeb.Live.Components.Devices, data: data} = message, socket) do
    send_update(message.module, id: message.id, data: message.data)

    devices = Map.get(data, :devices, [])

    socket =
      socket
      |> assign(:devices, devices)
      |> rebuild_network_graph()

    {:noreply, socket}
  end

  def handle_info(
        %{id: "resources", module: TunneldWeb.Live.Components.Resources, data: data} = message,
        socket
      ) do
    send_update(message.module, id: message.id, data: message.data)

    socket =
      socket
      |> maybe_refresh_sidebar_details(data)

    {:noreply, socket}
  end

  def handle_info(%{id: id, module: module, data: data}, socket) do
    if not is_nil(id) do
      send_update(module, id: id, data: data)
    end

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
      |> rebuild_network_graph()

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
  # Trigger and send options for the webAuthn
  #
  def handle_info(:configure_web_authn, socket) do
    challenge = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    user_id = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    public_key_options = %{
      challenge: challenge,
      rp: %{name: "Tunneld"},
      user: %{
        id: user_id,
        name: "Tunneld Gateway",
        displayName: "Tunneld Gateway"
      },
      pubKeyCredParams: [%{type: "public-key", alg: -7}],
      timeout: 60000,
      attestation: "none"
    }

    {:noreply,
     push_event(socket, "start_webauthn", %{
       publicKeyOptions: public_key_options
     })}
  end

  #
  # Revoke the login credentials
  #
  def handle_info(:revoke_login_creds, socket) do
    {:noreply,
     put_flash(socket, :info, "Auth reset. Next login will require a new password to be setup")}
  end

  #
  # Close the sidebar programatically without user interaction
  #
  def handle_info(:close_details, socket) do
    sidebar = %{
      is_open: false,
      view: Map.get(socket.assigns.sidebar, :view),
      selection: nil
    }

    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  def handle_info({:show_details, %{"id" => id, "type" => type}}, socket) do
    sidebar = %{
      is_open: true,
      view: get_sidebar_details(type, id),
      selection: sidebar_selection(type, id)
    }

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
    assign(socket, :modal, %{show: false, title: nil, body: %{}, actions: nil, type: :default})
  end

  defp modal_is_schema?(socket) do
    socket.assigns
    |> Map.get(:modal, %{})
    |> Map.get(:body, %{})
    |> case do
      %{"type" => "schema"} -> true
      _ -> false
    end
  end

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
      "connect_to_wireless_network" -> "Connecting to Wi‑Fi..."
      "disconnect_from_wireless_network" -> "Disconnecting Wi‑Fi..."
      "scan_for_wireless_networks" -> "Scanning Wi‑Fi..."
      "configure_web_authn" -> "Starting WebAuthn setup..."
      "configure_enable_control_plane" -> "Configuring control plane..."
      "configure_disable_control_plane" -> "Disconnecting control plane..."
      "configure_enable_environment" -> "Enabling device..."
      "configure_disable_environment" -> "Disabling device..."
      "revoke_login_creds" -> "Resetting login..."
      "update_blocklist" -> "Updating blocklist..."
      "configure_basic_auth" -> "Configuring Basic Auth..."
      "disable_basic_auth" -> "Disabling Basic Auth..."
      _ -> "Working on request..."
    end
  end

  defp rebuild_network_graph(socket) do
    internet? = get_in(socket.assigns, [:status, :internet]) || false
    devices = Map.get(socket.assigns, :devices, [])

    assign(socket, :network_graph, NetworkGraph.build(internet?, devices))
  end

end

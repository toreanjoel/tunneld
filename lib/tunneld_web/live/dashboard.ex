defmodule TunneldWeb.Live.Dashboard do
  @moduledoc """
  Dashboard V2 Page
  """
  use TunneldWeb, :live_view
  require Logger
  alias Tunneld.Servers.{Session}
  alias TunneldWeb.Router.Helpers, as: Routes

  # Components
  alias TunneldWeb.Live.Components.Sidebar.Details, as: SidebarDetails
  alias TunneldWeb.Live.Components.Welcome
  alias TunneldWeb.Live.Components.Resources
  alias TunneldWeb.Live.Components.Services
  alias TunneldWeb.Live.Components.Shares
  alias TunneldWeb.Live.Components.Devices
  alias TunneldWeb.Live.Components.Modal

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
    end

    # Check the scheme and domain to make sure it is possible to show
    uri_info = get_connect_info(socket, :uri)

    socket =
      socket
      |> assign(:client_id, client_id)
      |> assign(:uri_info, uri_info)
      # TODO: we need to setup web auth once we have a local cert for the device to be able to use it?
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
          view: nil
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
        body={@modal.body}
        actions={@modal.actions}
        client_id={@client_id}
      />
    </div>
    """
  end

  @spec sidebar(%{
          :allow_webauthn? => boolean(),
          :sidebar => %{is_open: boolean(), view: atom()},
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
      <button phx-click="close_details" class="absolute top-4 right-4">
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
          <%!-- Internet Access Placeholder --%>
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
            <.icon name="hero-user" class="h-15 w-15" />
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
        <%!-- Resources, Shares and Services  --%>
        <div class="flex flex-col md:flex-row w-full gap-6">
          <div class="flex-1"><.live_component id="resources" module={Resources} /></div>
          <div class="flex-1">
            <.live_component id="services" module={Services} />
          </div>
        </div>
        <%!-- Divider --%>
        <div class="border-t-2 border-dashed border-secondary" />

        <%!-- Shares --%>
        <div class="min-h-[200px]">
          <.live_component id="shares" module={Shares} />
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

    send(self(), %{action: action, data: data})
    {:noreply, socket}
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
  # Close the modal
  #
  def handle_event("modal_close", _params, socket) do
    modal_data = %{show: false, title: nil, body: %{}, actions: nil, type: :default}

    {:noreply, assign(socket, :modal, modal_data)}
  end

  @spec handle_info(%{id: String.t(), module: atom(), data: map()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @doc """
  This will have the parent dashboard view be responsible for sending update messages to components
  """
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
        Tunneld.Servers.Wlan.connect_with_pass(data["ssid"], data["password"])

      "disconnect_from_wireless_network" ->
        Tunneld.Servers.Wlan.disconnect()
        Process.send_after(self(), :delayed_scan, 3000)

      "scan_for_wireless_networks" ->
        send(self(), :scan_for_wireless_networks)

      #
      # WebAuthn configure
      #
      "configure_web_authn" ->
        send(self(), :configure_web_authn)

      #
      # Revoke Login Credentials
      #
      "revoke_login_creds" ->
        File.rm(Tunneld.Servers.Auth.path())
        send(self(), :revoke_login_creds)

      #
      # Shares
      #
      "add_artifact" ->
        Tunneld.Servers.Shares.add_artifact(data)

      "remove_artifact" ->
        %{"id" => id} = Jason.decode!(data)
        Tunneld.Servers.Shares.remove_artifact(id)
        send(self(), :close_details)

      "tunneld_settings" ->
        Tunneld.Servers.Shares.update_artifact(data, :tunneld)

      _ ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
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
      view: Map.get(socket.assigns.sidebar, :view)
    }

    {:noreply, assign(socket, :sidebar, sidebar)}
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
      "share" ->
        Tunneld.Servers.Shares.get_artifact(id)
        :share

      "service" ->
        Tunneld.Servers.Services.get_service_logs(id)
        :service

      "wlan" ->
        Tunneld.Servers.Wlan.scan_networks()
        :wlan

      "authentication" ->
        :authentication
    end
  end
end

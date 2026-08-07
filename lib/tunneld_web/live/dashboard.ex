defmodule TunneldWeb.Live.Dashboard do
  @moduledoc """
  Dashboard V2 Page
  """
  use TunneldWeb, :live_view
  require Logger
  alias Tunneld.Servers.Session
  alias Tunneld.Servers.Devices, as: DevicesServer
  alias TunneldWeb.Router.Helpers, as: Routes

  import TunneldWeb.Live.Components.SectionHeader

  alias TunneldWeb.Live.Components.Sidebar.Details, as: SidebarDetails
  alias TunneldWeb.Live.Components.Modal
  alias TunneldWeb.Live.Dashboard.Actions

  import TunneldWeb.Live.Components.TopBar
  import TunneldWeb.Live.Components.InternetCard
  import TunneldWeb.Live.Components.DnsCard
  import TunneldWeb.Live.Components.GaugeGrid
  import TunneldWeb.Live.Components.HelpIcon

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
    selection: nil,
    data: nil,
    containers: []
  }

  @link_poll_interval 15_000

  on_mount TunneldWeb.Hooks.CheckAuth

  def mount(_params, %{"client_id" => client_id} = _session, socket) do
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
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:devices")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:resources")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:system_resources")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "geolocation:device")
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:machines")
    end

    uri_info = get_connect_info(socket, :uri)
    devices = DevicesServer.fetch_devices()
    dns_server = Tunneld.Servers.DnsConfig.get_dns_server()

    internet_status =
      try do
        Tunneld.NetLink.upstream_up?()
      rescue
        _ -> false
      end

    socket =
      socket
      |> assign(:client_id, client_id)
      |> assign(:uri_info, uri_info)
      |> assign(modal: @modal_default)
      |> assign(sidebar: @sidebar_default)
      |> assign(status: %{internet: internet_status})
      |> assign(:devices, devices)
      |> assign(:pending_actions, %{})
      |> assign(:settings_menu_open, false)
      |> assign(:obfuscated, false)
      |> assign(:services_popover_open, false)
      |> assign(:dns_server, dns_server)
      |> assign(:devices_expanded, false)
      |> assign(:system_resources, %{})
      |> assign(:map_status, :loading)
      |> assign(:geo_location, nil)
      |> assign(:terminal_open, false)
      |> assign(:terminal_machine_id, nil)
      |> assign(:terminal_container, nil)

    socket =
      case Tunneld.Geolocation.get_location() do
        {:ok, loc} -> socket |> assign(:geo_location, loc) |> assign(:map_status, :ready)
        :stale -> assign(socket, :map_status, :stale)
        :unavailable -> assign(socket, :map_status, :unavailable)
      end

    if connected?(socket) do
      :timer.send_after(@link_poll_interval, :poll_link_state)
    end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-bg text-text-primary">
      <div class="absolute top-0 left-0 right-0 h-[760px] pointer-events-none z-0"
        style="background: radial-gradient(ellipse 80% 60% at 50% 0%, rgba(6,182,212,0.30) 0%, rgba(6,182,212,0.08) 30%, transparent 70%);">
      </div>
      <div class="absolute top-[720px] left-0 right-0 h-20 pointer-events-none z-0"
        style="background: linear-gradient(to bottom, rgba(11,10,20,0) 0%, #0B0A14 100%);">
      </div>

      <div class="relative z-[1]">
        <.top_bar
          services={services_list()}
          version={Application.get_env(:tunneld, :version)}
          update_available={Map.get(@system_resources, :is_latest, true) == false}
          new_version={Map.get(@system_resources, :new_version)}
          obfuscated={@obfuscated}
          settings_menu_open={@settings_menu_open}
          services_popover_open={@services_popover_open}
          device_id={Application.get_env(:tunneld, :metadata)[:device_id] || System.get_env("DEVICE_ID")}
        />

        <%= if !@devices_expanded do %>
          <main class="max-w-[1280px] mx-auto px-8 pt-2 pb-16">
            <div class="grid grid-cols-1 lg:grid-cols-[2fr_1fr] gap-6">
              <div class="h-full">
                <.live_component id="map_card" module={TunneldWeb.Live.Components.MapCard} geo_location={@geo_location} map_status={@map_status} />
              </div>
              <div class="grid grid-rows-[auto_1fr] gap-6 h-full">
                <div class="grid grid-cols-2 gap-6">
                  <.internet_card on={@status.internet} />
                  <.dns_card server={@dns_server} />
                </div>
                <.gauge_grid
                  cpu={Map.get(@system_resources, :cpu, 0)}
                  mem_pct={Map.get(@system_resources, :mem, 0)}
                  mem_used={Map.get(@system_resources, :mem_used, "—")}
                  mem_total={Map.get(@system_resources, :mem_total, "—")}
                  storage_pct={Map.get(@system_resources, :storage, 0)}
                  storage_used={Map.get(@system_resources, :storage_used, "—")}
                  storage_total={Map.get(@system_resources, :storage_total, "—")}
                  temp_value={Map.get(@system_resources, :temp, 0)}
                  temp_max={80}
                />
              </div>
            </div>

            <div class="mt-6">
              <.live_component id="resources" module={TunneldWeb.Live.Components.Resources} obfuscated={@obfuscated} />
            </div>

            <div class="mt-12">
              <.live_component id="machines" module={TunneldWeb.Live.Components.Machines} obfuscated={@obfuscated} />
            </div>

            <div class="mt-12">
              <.section_header>Local devices<.help_icon text="Devices connected to this Tunneld gateway's LAN port via Ethernet. Each device gets a DHCP lease and IP address from dnsmasq. Use Quick Expose to let devices create local resources via a curl command. Revoke IP to release the DHCP lease." /></.section_header>
              <div class="bg-surface border border-border rounded-xl p-6 h-24 flex items-center justify-between">
                <div class="flex items-center gap-5">
                  <span class="text-text-secondary inline-flex">
                    <.icon name="hero-computer-desktop" class="w-8 h-8" />
                  </span>
                  <span class="text-[28px] text-text-primary font-medium -tracking-[0.02em]">
                    <%= length(@devices) %>
                  </span>
          <span class="text-sm text-text-secondary leading-[1.3] max-w-[180px]">
            local devices
          </span>
                </div>
                <button class="ghost-btn" phx-click="toggle_devices_expanded">
                  View all devices
                  <.icon name="hero-chevron-right" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </main>
        <% else %>
          <main class="max-w-[1280px] mx-auto px-8 pt-2 pb-16">
            <button class="ghost-btn mb-6" phx-click="toggle_devices_expanded">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to dashboard
            </button>
            <.live_component id="devices" module={TunneldWeb.Live.Components.Devices} obfuscated={@obfuscated} />
          </main>
        <% end %>
      </div>

      <%= if @sidebar.is_open do %>
        <div class="fixed inset-0 bg-black/50 z-40" phx-click="close_details" />
      <% end %>
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

      <%= if @terminal_open do %>
        <.terminal_modal machine_id={@terminal_machine_id} container={@terminal_container} client_id={@client_id} />
      <% end %>
    </div>
    """
  end

  defp terminal_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60" phx-click="close_terminal" phx-window-keydown="close_terminal" phx-key="escape">
      <div class="bg-bg border border-border rounded-lg w-[95%] max-w-6xl h-[90%] flex flex-col" phx-click="ignore">
        <div class="flex items-center justify-between p-3 border-b border-border">
          <div class="text-sm font-medium">
            <.icon name="hero-command-line" class="w-4 h-4 inline mr-1" />
            shell: <%= @container %>
          </div>
          <button phx-click="close_terminal" class="ghost-btn text-xs">close</button>
        </div>
        <div
          id={"terminal-#{@machine_id}-#{@container}"}
          phx-hook="Terminal"
          data-topic={"exec:#{@machine_id}:#{@container}"}
          data-client-id={@client_id}
          class="flex-1 bg-black overflow-hidden p-2 cursor-text"
        >
          <pre class="text-xs font-mono text-green-400 whitespace-pre-wrap h-full overflow-auto m-0"></pre>
          <input type="text" class="terminal-input opacity-0 absolute -z-10 w-0 h-0" autocomplete="off" autofocus />
        </div>
      </div>
    </div>
    """
  end

  def sidebar(%{sidebar: sidebar, uri_info: uri_info} = assigns) do
    assigns =
      assigns
      |> assign(:sidebar, sidebar)
      |> assign(:uri_info, uri_info)

    ~H"""
    <div
      :if={@sidebar.is_open}
      class="fixed top-0 right-0 z-50 h-screen w-screen lg:w-[35%] lg:max-w-[700px] shadow-lg transition-transform duration-300 ease-in-out"

      style="background-color: var(--surface);"
    >
      <button phx-click="close_details" class="absolute top-4 right-4 z-10 ghost-icon w-9 h-9 flex items-center justify-center">
        <.icon class="w-5 h-5" name="hero-x-mark" />
      </button>

      <div class="h-full overflow-y-auto system-scroll bg-surface">
        <div class="min-h-full">
        <.live_component
          id="sidebar_details"
          module={SidebarDetails}
          view={@sidebar.view}
          uri_info={@uri_info}
          selection={@sidebar.selection}
          data={@sidebar.data}
          containers={@sidebar.containers}
          obfuscated={@obfuscated}
        />
        </div>
      </div>
    </div>
    """
  end

  defp services_list do
    status = Tunneld.Servers.Services.get_status()

    for {name, up?} <- status do
      %{name: to_string(name), up: up?}
    end
  end

  def handle_event("disable_tunneld", _params, socket) do
    modal_data = modal_open(%{
      title: "Disable Tunneld?",
      description: "This will stop the gateway, DHCP, and DNS services. All LAN devices will lose connectivity.",
      body: %{"type" => "code_blocks", "data" => [
        %{"title" => "To re-enable, SSH into the device and run", "code" => "sudo systemctl start dnsmasq\nsudo systemctl start tunneld"}
      ]},
      actions: %{"title" => "Disable", "payload" => %{"type" => "disable_tunneld_service", "data" => %{}}}
    })

    {:noreply, socket |> assign(:modal, modal_data) |> assign(:settings_menu_open, false)}
  end

  def handle_event("enable_tunneld", _params, socket) do
    {:noreply, start_action("enable_tunneld_service", %{}, socket) |> assign(:settings_menu_open, false)}
  end

  def handle_event("restart_device", _params, socket) do
    modal_data = modal_open(%{
      title: "Restart Device?",
      description: "This will restart the gateway service. The dashboard will be temporarily unavailable.",
      body: %{"type" => "string", "data" => "All active connections will be interrupted. The device will come back online automatically."},
      actions: %{"title" => "Restart", "payload" => %{"type" => "restart_device", "data" => %{}}}
    })

    {:noreply, socket |> assign(:modal, modal_data) |> assign(:settings_menu_open, false)}
  end

  def handle_event("toggle_obfuscation", %{"obfuscated" => obfuscated}, socket) do
    obfuscated = obfuscated in ["true", true]
    {:noreply, socket |> assign(:obfuscated, obfuscated) |> push_event("update_obfuscation", %{obfuscated: obfuscated})}
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

  def handle_event("show_details", %{"id" => id, "type" => "machine"}, socket) do
    {:noreply, open_machine_sidebar(socket, id)}
  end

  def handle_event("show_details", %{"id" => id, "type" => type}, socket) do
    sidebar = sidebar_open(get_sidebar_details(type, id), sidebar_selection(type, id))
    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  def handle_event("toggle_share_access", params, socket) do
    {:noreply, start_action("toggle_share_access", params, socket)}
  end

  def handle_event("close_details", _, socket) do
    sidebar = sidebar_close(socket.assigns.sidebar)
    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  def handle_event("confirm_logout", _params, socket) do
    modal_data = modal_open(%{
      title: "Log out?",
      body: %{"type" => "string", "data" => "You will need to enter your credentials to access the dashboard again."},
      actions: %{"title" => "Log out", "payload" => %{"type" => "logout", "data" => %{}}}
    })

    {:noreply, socket |> assign(:modal, modal_data) |> assign(:settings_menu_open, false)}
  end

  def handle_event("trigger_action", params, socket) do
    action = params["action"]
    data = Jason.decode!(params["data"])
    {:noreply, start_action(action, data, socket)}
  end

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

    {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal_data))}
  end

  def handle_event("modal_close", _params, socket) do
    {:noreply, assign(socket, :modal, @modal_default)}
  end

  def handle_event("toggle_services_popover", _params, socket) do
    {:noreply, assign(socket, :services_popover_open, !socket.assigns.services_popover_open)}
  end

  def handle_event("toggle_devices_expanded", _params, socket) do
    {:noreply, assign(socket, :devices_expanded, !socket.assigns.devices_expanded)}
  end

  # --- Machines ---

  def handle_event("enroll_machine_modal", _params, socket) do
    modal_data = %{
      show: true,
      title: "Add Machine",
      description: nil,
      body: %{
        "type" => "schema",
        "data" => Tunneld.Schema.Machine.data(),
        "default_values" => %{"ssh_port" => 22, "location" => "local"},
        "action" => "enroll_machine"
      },
      actions: nil,
      type: :default
    }

    {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal_data))}
  end

  def handle_event("create_container_modal", %{"id" => id}, socket) do
    case Tunneld.Machines.get(id) do
      {:ok, machine} ->
        caps = machine["capabilities"] || %{}

        modal_data = %{
          show: true,
          title: "New Container/VM",
          description: "Provision an Incus container or VM on #{machine["name"]}.",
          body: %{
            "type" => "schema",
            "data" =>
              Tunneld.Schema.Container.data(%{
                machine_id: id,
                kvm: caps["kvm"] == true,
                location: machine["location"],
                cpu_count: caps["cpu_count"],
                memory_mb: caps["memory_mb"]
              }),
            "default_values" => %{"type" => "container", "network" => "bridge"},
            "action" => "create_container"
          },
          actions: nil,
          type: :default
        }

        {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal_data))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Machine not found")}
    end
  end

  def handle_event("expose_container_modal", %{"id" => id, "name" => name}, socket) do
    modal_data = %{
      show: true,
      title: "Expose Container",
      description: "Make #{name} reachable on the subnet via a reverse SSH tunnel.",
      body: %{
        "type" => "schema",
        "data" => Tunneld.Schema.Expose.data(%{machine_id: id, container: name}),
        "default_values" => %{"machine_id" => id, "container" => name},
        "action" => "expose_container"
      },
      actions: nil,
      type: :default
    }

    {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal_data))}
  end

  def handle_event("probe_machine", %{"id" => id}, socket) do
    case Tunneld.Machines.probe(id) do
      {:ok, _} ->
        send(self(), {:machines_changed})
        {:noreply, put_flash(socket, :info, "Probe complete")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Probe failed: #{inspect(reason)}")}
    end
  end

  def handle_event("remove_machine", %{"id" => id}, socket) do
    case Tunneld.Machines.remove(id) do
      :ok ->
        send(self(), {:machines_changed})
        {:noreply, put_flash(socket, :info, "Machine removed")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not remove machine")}
    end
  end

  def handle_event("start_container", %{"id" => id, "name" => name}, socket) do
    case Tunneld.Machines.start_container(id, name) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "#{name} started")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not start #{name}")}
    end
  end

  def handle_event("stop_container", %{"id" => id, "name" => name}, socket) do
    case Tunneld.Machines.stop_container(id, name) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "#{name} stopped")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not stop #{name}")}
    end
  end

  def handle_event("delete_container", %{"id" => id, "name" => name}, socket) do
    case Tunneld.Machines.delete_container(id, name) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "#{name} deleted")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not delete #{name}")}
    end
  end

  def handle_event("open_terminal", %{"id" => id, "name" => name}, socket) do
    socket =
      socket
      |> assign(:terminal_open, true)
      |> assign(:terminal_machine_id, id)
      |> assign(:terminal_container, name)

    {:noreply, socket}
  end

  def handle_event("close_terminal", _params, socket) do
    socket =
      socket
      |> assign(:terminal_open, false)
      |> assign(:terminal_machine_id, nil)
      |> assign(:terminal_container, nil)

    {:noreply, socket}
  end

  def handle_info(
        %{id: "devices", module: TunneldWeb.Live.Components.Devices, data: data} = message,
        socket
      ) do
    devices = Map.get(data, :devices, [])

    if socket.assigns.devices_expanded do
      send_update(message.module, id: message.id, data: message.data, obfuscated: socket.assigns.obfuscated)
    end

    {:noreply, assign(socket, :devices, devices)}
  end

  def handle_info(%{id: "resources", module: TunneldWeb.Live.Components.Resources, data: data} = message, socket) do
    send_update(message.module, id: message.id, data: message.data, obfuscated: socket.assigns.obfuscated)
    socket = maybe_refresh_sidebar_details(socket, data)
    {:noreply, socket}
  end

  def handle_info(%{id: "sidebar_details", module: _module, data: %{dns_server: dns_server}}, socket) do
    {:noreply, assign(socket, :dns_server, dns_server)}
  end

  def handle_info(%{id: "system_resources", module: TunneldWeb.Live.Components.SystemResources, data: data}, socket) do
    resources = Map.get(data, :resources, %{})
    # Preserve update check state from existing assignment
    resources =
      resources
      |> Map.put(:is_latest, Map.get(socket.assigns.system_resources, :is_latest, true))
      |> Map.put(:new_version, Map.get(socket.assigns.system_resources, :new_version))

    {:noreply, assign(socket, :system_resources, resources)}
  end

  def handle_info(%{id: id, module: module, data: data}, socket) do
    if not is_nil(id) do
      send_update(module, id: id, data: data, obfuscated: socket.assigns.obfuscated)
    end

    {:noreply, socket}
  end

  def handle_info(%{id: "machines", event: _, data: _}, socket) do
    send_update(TunneldWeb.Live.Components.Machines, id: "machines", data: %{})
    {:noreply, socket}
  end

  def handle_info({:machines_changed}, socket) do
    send_update(TunneldWeb.Live.Components.Machines, id: "machines", data: %{})
    {:noreply, socket}
  end

  def handle_info(:poll_link_state, socket) do
    :timer.send_after(@link_poll_interval, :poll_link_state)

    status =
      try do
        Tunneld.NetLink.upstream_up?()
      rescue
        _ -> false
      end

    {:noreply, assign(socket, status: %{internet: status})}
  end

  def handle_info(%{type: :internet, status: _status}, socket) do
    # Link state is polled locally via :poll_link_state; ignore any stray
    # legacy broadcasts on this topic.
    {:noreply, socket}
  end

  def handle_info(%{type: type, message: message}, socket) do
    type = if type in [:info, :error], do: type, else: :info
    Process.send_after(self(), :clear_flash, 3500)
    {:noreply, put_flash(socket, type, message)}
  end

  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  def handle_info(%{action: action, data: data}, socket) do
    {:noreply, start_action(action, data, socket)}
  end

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

  def handle_info({:action_done, ref, action, _result}, socket)
      when action in ["add_device_tag", "remove_device_tag"] do
    pending = Map.get(socket.assigns.pending_actions, ref, %{})
    devices =
      DevicesServer.fetch_devices()
      |> Enum.map(fn d ->
        d
        |> Map.put(:expose_allowed, Tunneld.Servers.ExposeAllowed.allowed?(d.mac))
        |> Map.put(:tags, Tunneld.Servers.DeviceTags.get_tags(d.mac))
      end)

    socket =
      socket
      |> assign(:pending_actions, Map.delete(socket.assigns.pending_actions, ref))
      |> assign(:devices, devices)
      |> maybe_close_modal_after_success(pending)

    {:noreply, socket}
  end

  def handle_info({:action_done, ref, action, result}, socket)
      when action in ["enroll_machine", "create_container", "expose_container"] do
    pending = Map.get(socket.assigns.pending_actions, ref, %{})

    socket =
      case unwrap_result(result) do
        {:ok, data} ->
          socket
          |> assign(:pending_actions, Map.delete(socket.assigns.pending_actions, ref))
          |> maybe_close_modal_after_success(pending)
          |> machine_action_flash(action, data)

        {:error, reason} ->
          Logger.error("Machine action failed: #{inspect(reason)}")

          socket
          |> assign(:pending_actions, Map.delete(socket.assigns.pending_actions, ref))
          |> maybe_keep_modal_open(pending)
          |> put_flash(:error, "Action failed: #{machine_error(action, reason)}")
      end

    send(self(), {:machines_changed})
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

  def handle_info(:do_logout, socket) do
    Session.delete(socket.assigns.client_id)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, TunneldWeb.Live.Login))}
  end

  def handle_info(:revoke_login_creds, socket) do
    {:noreply, put_flash(socket, :info, "Auth reset. Next login will require a new password to be setup")}
  end

  def handle_info(:close_details, socket) do
    {:noreply, assign(socket, :sidebar, sidebar_close(socket.assigns.sidebar))}
  end

  def handle_info({:show_details, %{"id" => id, "type" => "machine"}}, socket) do
    {:noreply, open_machine_sidebar(socket, id)}
  end

  def handle_info({:show_details, %{"id" => id, "type" => type}}, socket) do
    sidebar = sidebar_open(get_sidebar_details(type, id), sidebar_selection(type, id))
    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  def handle_info({:location_updated, location}, socket) do
    {:noreply,
     socket
     |> assign(:geo_location, location)
     |> assign(:map_status, :ready)}
  end

  def handle_info(:location_unavailable, socket) do
    if socket.assigns.geo_location do
      {:noreply, assign(socket, :map_status, :stale)}
    else
      {:noreply, assign(socket, :map_status, :unavailable)}
    end
  end

  def handle_info(:geo_failed, socket) do
    if socket.assigns.geo_location do
      {:noreply, assign(socket, :map_status, :stale)}
    else
      {:noreply, assign(socket, :map_status, :geo_failed)}
    end
  end

  def handle_info(:location_stale, socket) do
    if socket.assigns.geo_location do
      {:noreply, assign(socket, :map_status, :stale)}
    else
      {:noreply, assign(socket, :map_status, :unavailable)}
    end
  end

  defp get_sidebar_details(type, id) do
    case type do
      "resource" ->
        Tunneld.Servers.Resources.get_resource(id)
        :resource

      "machine" ->
        case Tunneld.Machines.get(id) do
          {:ok, machine} -> machine
          _ -> %{}
        end

      "service" ->
        :system_overview

      "ethernet" ->
        :ethernet

      "dns_server" ->
        :dns_server

      "authentication" ->
        :authentication
    end
  end

  defp sidebar_selection("resource", id) when is_binary(id), do: %{type: :resource, id: id}
  defp sidebar_selection("machine", id) when is_binary(id), do: %{type: :machine, id: id}
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

  defp start_message(action) do
    case action do
      "add_share" -> "Adding resource..."
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
      "set_dns_server" -> "Updating DNS server..."
      "revoke_login_creds" -> "Resetting login..."
      "restart_device" -> "Restarting device..."
      _ -> "Working on request..."
    end
  end

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
    %{is_open: true, view: view, selection: selection, data: nil, containers: []}
  end

  defp open_machine_sidebar(socket, id) do
    case Tunneld.Machines.get(id) do
      {:ok, machine} ->
        containers =
          case Tunneld.Machines.list_containers(id) do
            {:ok, c} -> c
            _ -> []
          end

        sidebar = %{
          is_open: true,
          view: :machine,
          selection: %{type: :machine, id: id},
          data: machine,
          containers: containers
        }

        assign(socket, :sidebar, sidebar)

      _ ->
        assign(socket, :sidebar, @sidebar_default)
    end
  end

  defp sidebar_close(sidebar) when is_map(sidebar) do
    %{is_open: false, view: Map.get(sidebar, :view), selection: nil, data: nil, containers: []}
  end

  defp machine_action_flash(socket, "enroll_machine", %{"public_key" => pub}) when is_binary(pub) do
    socket =
      put_flash(
        socket,
        :info,
        "Machine enrolled. Install this public key on the target: #{pub}"
      )

    socket
  end

  defp machine_action_flash(socket, "enroll_machine", %{"machine" => %{"name" => name}}) do
    put_flash(socket, :info, "Machine #{name} enrolled. You can now install its key and probe it.")
  end

  defp machine_action_flash(socket, "create_container", %{"name" => name}) do
    put_flash(socket, :info, "Container #{name} created")
  end

  defp machine_action_flash(socket, "expose_container", %{"lan_url" => lan_url})
      when not is_nil(lan_url) do
    put_flash(socket, :info, "Exposed on the subnet at #{lan_url}")
  end

  defp machine_action_flash(socket, "expose_container", _result) do
    put_flash(socket, :info, "Exposed on the subnet")
  end

  defp machine_action_flash(socket, _action, _result), do: socket

  # start_action wraps perform/3 as {:ok, perform(...)}. perform/3 itself returns
  # {:ok, data} | {:error, reason} for machine actions, so we unwrap both layers.
  defp unwrap_result({:ok, {:ok, data}}), do: {:ok, data}
  defp unwrap_result({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_result({:ok, data}), do: {:ok, data}
  defp unwrap_result({:error, reason}), do: {:error, reason}
  defp unwrap_result(other), do: {:ok, other}

  defp machine_error("enroll_machine", reason), do: "enrollment failed: #{inspect(reason)}"
  defp machine_error("create_container", reason), do: "container creation failed: #{inspect(reason)}"
  defp machine_error("expose_container", reason), do: "expose failed: #{inspect(reason)}"
  defp machine_error(_action, reason), do: inspect(reason)
end

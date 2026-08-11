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
    listeners: [],
    listeners_loading: false,
    listeners_error: nil
  }

  @link_poll_interval 15_000

  # WireGuard comes up (or drops) entirely out of band - a provider firewall
  # rule, a handshake finally completing, a VM reboot. None of those produce a
  # tunneld event, so nothing re-renders and the UI keeps showing whatever the
  # overlay looked like the last time a machine was created or edited. That is
  # why an overlay that had come up still read "down" until the panel was
  # closed and reopened, and why the machine list never went green. Poll it.
  @overlay_poll_interval 15_000

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
      |> assign(:enroll_wizard_open, false)
      |> assign(:terminal_modal, nil)
      |> assign(:map_nodes, map_nodes())

    socket =
      case Tunneld.Geolocation.get_location() do
        {:ok, loc} -> socket |> assign(:geo_location, loc) |> assign(:map_status, :ready)
        :stale -> assign(socket, :map_status, :stale)
        :unavailable -> assign(socket, :map_status, :unavailable)
      end

    if connected?(socket) do
      :timer.send_after(@link_poll_interval, :poll_link_state)
      :timer.send_after(@overlay_poll_interval, :poll_overlay_state)
    end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-bg text-text-primary">
      <div
        class="absolute top-0 left-0 right-0 h-[760px] pointer-events-none z-0"
        style="background: radial-gradient(ellipse 80% 60% at 50% 0%, rgba(6,182,212,0.30) 0%, rgba(6,182,212,0.08) 30%, transparent 70%);"
      >
      </div>
      <div
        class="absolute top-[720px] left-0 right-0 h-20 pointer-events-none z-0"
        style="background: linear-gradient(to bottom, rgba(11,10,20,0) 0%, #0B0A14 100%);"
      >
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
          device_id={
            Application.get_env(:tunneld, :metadata)[:device_id] || System.get_env("DEVICE_ID")
          }
        />

        <%= if !@devices_expanded do %>
          <main class="max-w-[1280px] mx-auto px-8 pt-2 pb-16">
            <div class="grid grid-cols-1 lg:grid-cols-[2fr_1fr] gap-6">
              <div class="h-full">
                <.live_component
                  id="map_card"
                  module={TunneldWeb.Live.Components.MapCard}
                  geo_location={@geo_location}
                  map_status={@map_status}
                  nodes={@map_nodes}
                />
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
              <.live_component
                id="resources"
                module={TunneldWeb.Live.Components.Resources}
                obfuscated={@obfuscated}
              />
            </div>

            <div class="mt-12">
              <.live_component
                id="machines"
                module={TunneldWeb.Live.Components.Machines}
                obfuscated={@obfuscated}
              />
            </div>

            <div class="mt-12">
              <.section_header>
                Local devices<.help_icon text="Devices connected to this Tunneld gateway's LAN port via Ethernet. Each device gets a DHCP lease and IP address from dnsmasq. Use Quick Expose to let devices create local resources via a curl command. Revoke IP to release the DHCP lease." />
              </.section_header>
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
                  View all devices <.icon name="hero-chevron-right" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </main>
        <% else %>
          <main class="max-w-[1280px] mx-auto px-8 pt-2 pb-16">
            <button class="ghost-btn mb-6" phx-click="toggle_devices_expanded">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to dashboard
            </button>
            <.live_component
              id="devices"
              module={TunneldWeb.Live.Components.Devices}
              obfuscated={@obfuscated}
              egress_machines={egress_machines()}
            />
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

      <.live_component
        module={TunneldWeb.Live.Components.EnrollmentWizard}
        id="enrollment_wizard"
        open={@enroll_wizard_open}
      />

      <%= if @terminal_modal do %>
        <div class="fixed inset-0 bg-black/80 z-[60]" phx-click="close_terminal" />
        <div class="fixed inset-4 md:inset-8 lg:inset-16 z-[70] flex flex-col bg-[#0B0A14] rounded-xl border border-border overflow-hidden">
          <div class="flex items-center justify-between px-4 py-3 border-b border-border">
            <div class="flex items-center gap-3">
              <.icon name="hero-command-line" class="w-5 h-5 text-accent" />
              <span class="text-sm font-medium">Terminal: <%= @terminal_modal.machine_name %></span>
              <%!-- Written by the Terminal hook. Must be ignored by DOM patching or the
                   dashboard's periodic re-renders reset it to "Initializing...". --%>
              <div
                id="terminal-status"
                phx-update="ignore"
                class="terminal-status flex items-center gap-2 text-xs text-text-tertiary"
              >
                <span class="terminal-status-icon"></span>
                <span class="terminal-status-text">Initializing...</span>
              </div>
            </div>
            <button
              phx-click="close_terminal"
              class="ghost-icon w-8 h-8 flex items-center justify-center"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <%!-- phx-update="ignore" is REQUIRED. xterm.js injects its own canvas/rows
               into .terminal-container; without this, the next LiveView diff (devices
               sync at 10s, link poll at 15s, etc.) reconciles that subtree back to the
               empty server-rendered div and the terminal visibly vanishes. --%>
          <div
            id={"terminal-#{@terminal_modal.machine_id}"}
            phx-hook="Terminal"
            phx-update="ignore"
            data-machine-id={@terminal_modal.machine_id}
            class="flex-1 flex flex-col"
          >
            <div class="terminal-container flex-1 p-2"></div>
          </div>
        </div>
      <% end %>
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
    modal_data =
      modal_open(%{
        title: "Disable Tunneld?",
        description:
          "This will stop the gateway, DHCP, and DNS services. All LAN devices will lose connectivity.",
        body: %{
          "type" => "code_blocks",
          "data" => [
            %{
              "title" => "To re-enable, SSH into the device and run",
              "code" => "sudo systemctl start dnsmasq\nsudo systemctl start tunneld"
            }
          ]
        },
        actions: %{
          "title" => "Disable",
          "payload" => %{"type" => "disable_tunneld_service", "data" => %{}}
        }
      })

    {:noreply, socket |> assign(:modal, modal_data) |> assign(:settings_menu_open, false)}
  end

  def handle_event("enable_tunneld", _params, socket) do
    {:noreply,
     start_action("enable_tunneld_service", %{}, socket) |> assign(:settings_menu_open, false)}
  end

  def handle_event("restart_device", _params, socket) do
    modal_data =
      modal_open(%{
        title: "Restart Device?",
        description:
          "This will restart the gateway service. The dashboard will be temporarily unavailable.",
        body: %{
          "type" => "string",
          "data" =>
            "All active connections will be interrupted. The device will come back online automatically."
        },
        actions: %{
          "title" => "Restart",
          "payload" => %{"type" => "restart_device", "data" => %{}}
        }
      })

    {:noreply, socket |> assign(:modal, modal_data) |> assign(:settings_menu_open, false)}
  end

  def handle_event("toggle_obfuscation", %{"obfuscated" => obfuscated}, socket) do
    obfuscated = obfuscated in ["true", true]

    {:noreply,
     socket
     |> assign(:obfuscated, obfuscated)
     |> push_event("update_obfuscation", %{obfuscated: obfuscated})}
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
    modal_data =
      modal_open(%{
        title: "Log out?",
        body: %{
          "type" => "string",
          "data" => "You will need to enter your credentials to access the dashboard again."
        },
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

  def handle_event("enroll_machine_modal", _params, socket) do
    {:noreply, assign(socket, :enroll_wizard_open, true)}
  end

  def handle_event("make_exit_node", %{"id" => id}, socket) do
    # Always re-apply. The old code short-circuited on exit_capable?, which is a
    # local JSON flag, while the rules it stands for live in the target's
    # iptables and do not survive a reboot. ensure_exit_capable/1 is idempotent,
    # so re-running is also the repair path.
    {result, label} =
      case Tunneld.Machines.get(id) do
        {:ok, machine} ->
          {Tunneld.Egress.ensure_exit_capable(machine), machine["name"] || id}

        _ ->
          {{:error, "machine not found"}, id}
      end

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: if(match?({:ok, _}, result), do: :info, else: :error),
      message: format_exit_result(result, label)
    })

    send(self(), {:machines_changed})
    {:noreply, socket}
  end

  def handle_event("reconcile_machine", %{"id" => id}, socket) do
    result =
      case Tunneld.Machines.get(id) do
        {:ok, machine} ->
          # One "sync" action: ensure the overlay is up, re-apply the exit
          # rules (they are lost on the target's reboot), probe, check drift.
          overlay = Tunneld.Overlay.ensure_peer(machine)

          exit_result =
            case overlay do
              {:ok, _} -> Tunneld.Egress.ensure_exit_capable(machine)
              _ -> :skipped
            end

          probe = Tunneld.Machines.probe(id)
          reconcile = Tunneld.Reconcile.reconcile(machine, repair: true)
          %{overlay: overlay, exit: exit_result, probe: probe, reconcile: reconcile}

        _ ->
          %{error: "machine not found"}
      end

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: :info,
      message: format_reconcile_result(result)
    })

    send(self(), {:machines_changed})
    {:noreply, socket}
  end

  def handle_event("remove_machine", %{"id" => id}, socket) do
    modal = %{
      show: true,
      title: "Delete machine",
      description: "This permanently removes the machine and its SSH key. This cannot be undone.",
      body: %{"type" => "string", "data" => "Are you sure you want to delete this machine?"},
      actions: %{
        "title" => "Delete",
        "payload" => %{"type" => "remove_machine", "data" => %{"id" => id}}
      },
      type: :default
    }

    {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal))}
  end

  def handle_event("view_ssh_key", %{"id" => id}, socket) do
    ssh_user =
      case Tunneld.Machines.get(id) do
        {:ok, machine} -> machine["ssh_user"] || "root"
        _ -> "root"
      end

    case Tunneld.Machines.SSH.public_key_string(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "No SSH key found for this machine")}

      pub ->
        blocks = [
          %{
            "title" => "1. Enable the SSH server (if not already running)",
            "code" =>
              "sudo apt update && sudo apt install -y openssh-server && sudo systemctl enable --now ssh"
          },
          %{
            "title" => "2. Install the SSH key on the target",
            "code" =>
              "mkdir -p ~/.ssh && echo '#{String.trim(pub)}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
          },
          %{
            "title" => "3. Give #{ssh_user} passwordless sudo (required for service management)",
            "code" =>
              "echo '#{ssh_user} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/#{ssh_user} && sudo chmod 440 /etc/sudoers.d/#{ssh_user}"
          }
        ]

        modal = %{
          show: true,
          title: "SSH key & setup",
          description:
            "Run these on the target machine so tunneld can connect over SSH and configure services.",
          body: %{"type" => "code_blocks", "data" => blocks},
          actions: nil,
          type: :default
        }

        {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal))}
    end
  end

  def handle_event("ssh_connect", %{"id" => id}, socket) do
    case Tunneld.Machines.get(id) do
      {:ok, machine} ->
        ssh_user = machine["ssh_user"] || "root"
        ssh_port = machine["ssh_port"] || 22
        address = machine["overlay_ip"] || machine["address"] || "unknown"
        key_path = Tunneld.Machines.SSH.private_key_path(id)

        ssh_cmd = "ssh -i #{key_path} -p #{ssh_port} #{ssh_user}@#{address}"

        modal = %{
          show: true,
          title: "SSH to #{machine["name"] || id}",
          description: "Connect to this machine via SSH. Copy the command below.",
          body: %{"type" => "code", "data" => ssh_cmd, "label" => "SSH command:"},
          actions: nil,
          type: :default
        }

        {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal))}

      _ ->
        {:noreply, put_flash(socket, :error, "Machine not found")}
    end
  end

  def handle_event("open_terminal", %{"id" => id}, socket) do
    case Tunneld.Machines.get(id) do
      {:ok, machine} ->
        terminal_modal = %{
          machine_id: id,
          machine_name: machine["name"] || id
        }

        {:noreply, assign(socket, :terminal_modal, terminal_modal)}

      _ ->
        {:noreply, put_flash(socket, :error, "Machine not found")}
    end
  end

  def handle_event("close_terminal", _params, socket) do
    {:noreply, assign(socket, :terminal_modal, nil)}
  end

  def handle_event("add_pool_member_modal", %{"id" => id}, socket) do
    modal_data = %{
      show: true,
      title: "Add Backend",
      description: "Add a backend (IP:PORT) to this resource's pool.",
      body: %{
        "type" => "schema",
        "data" => %{
          "title" => "Add Backend",
          "type" => "object",
          "properties" => %{
            "id" => %{
              "type" => "string",
              "ui:widget" => "hidden",
              "readOnly" => true,
              "default" => id
            },
            "backend" => %{
              "type" => "string",
              "pattern" => "^[^\s:]+:[0-9]{1,5}$",
              "description" => "Backend address (IP:PORT), e.g. 10.0.0.5:3000"
            }
          },
          "required" => ["id", "backend"]
        },
        "default_values" => %{"id" => id},
        "action" => "add_pool_member"
      },
      actions: nil,
      type: :default
    }

    {:noreply, assign(socket, :modal, Map.merge(socket.assigns.modal, modal_data))}
  end

  def handle_event(
        "make_listener_resource",
        %{"machine_id" => id, "addr" => addr, "port" => port, "proc" => proc} = _params,
        socket
      ) do
    name = sanitize_resource_name("#{proc}-#{port}")

    # The pool should point at the address tunneld can actually route to: for
    # a same-subnet machine that is the LAN IP, for a remote machine it is the
    # overlay IP (WireGuard) - never the raw bind address (often 0.0.0.0).
    backend_addr =
      case Tunneld.Machines.get(id) do
        {:ok, machine} -> Tunneld.Overlay.address_for(machine)
        _ -> addr
      end

    resource = %{
      "name" => name,
      "description" => "Listener #{addr}:#{port} on machine #{id} (#{proc})",
      "pool" => ["#{backend_addr}:#{port}"],
      "expose_source" => "listener",
      "expose_machine_id" => id
    }

    _ = Tunneld.Servers.Resources.add_share(resource)
    socket = assign(socket, :listener_made, name)

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: :info,
      message: "Resource '#{name}' created from listener #{backend_addr}:#{port}"
    })

    {:noreply, socket}
  end

  # The enrollment wizard is a live_component whose open state is owned by
  # this parent (@enroll_wizard_open). When the wizard asks to close, reset
  # the parent flag so the modal stays closed on subsequent re-renders.
  def handle_info(:wizard_closed, socket) do
    {:noreply, assign(socket, :enroll_wizard_open, false)}
  end

  def handle_info(
        %{id: "devices", module: TunneldWeb.Live.Components.Devices, data: data} = message,
        socket
      ) do
    devices = Map.get(data, :devices, [])

    if socket.assigns.devices_expanded do
      send_update(message.module,
        id: message.id,
        data: message.data,
        obfuscated: socket.assigns.obfuscated,
        egress_machines: egress_machines()
      )
    end

    {:noreply, assign(socket, :devices, devices)}
  end

  def handle_info(
        %{id: "resources", module: TunneldWeb.Live.Components.Resources, data: data} = message,
        socket
      ) do
    send_update(message.module,
      id: message.id,
      data: message.data,
      obfuscated: socket.assigns.obfuscated
    )

    socket = maybe_refresh_sidebar_details(socket, data)
    {:noreply, socket}
  end

  def handle_info(
        %{id: "sidebar_details", module: _module, data: %{dns_server: dns_server}},
        socket
      ) do
    {:noreply, assign(socket, :dns_server, dns_server)}
  end

  def handle_info(
        %{id: "system_resources", module: TunneldWeb.Live.Components.SystemResources, data: data},
        socket
      ) do
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
    {:noreply, assign(socket, :map_nodes, map_nodes())}
  end

  def handle_info({:machines_changed}, socket) do
    send_update(TunneldWeb.Live.Components.Machines, id: "machines", data: %{})
    {:noreply, assign(socket, :map_nodes, map_nodes())}
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

  # Re-render whatever displays overlay state. `send_update` re-runs the
  # machines component's update/2, which re-reads `wg show` per machine, so the
  # status dot settles on its own once a tunnel comes up.
  #
  # The sidebar is refreshed in place rather than through
  # `refresh_machine_sidebar/2`: that one also re-fetches listeners, which is an
  # SSH round trip per machine and has no business running on a timer.
  def handle_info(:poll_overlay_state, socket) do
    :timer.send_after(@overlay_poll_interval, :poll_overlay_state)

    send_update(TunneldWeb.Live.Components.Machines, id: "machines", data: %{})

    {:noreply, refresh_sidebar_overlay(socket)}
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
      when action in ["enroll_machine"] do
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

    socket = maybe_refresh_machine_sidebar(socket, pending)
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
    {:noreply,
     put_flash(socket, :info, "Auth reset. Next login will require a new password to be setup")}
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

  def handle_async(:fetch_listeners, {:ok, {:ok, listeners}}, socket) do
    sidebar = socket.assigns.sidebar
    sidebar = %{sidebar | listeners: listeners, listeners_loading: false, listeners_error: nil}
    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  def handle_async(:fetch_listeners, {:ok, {:error, reason}}, socket) do
    sidebar = socket.assigns.sidebar
    sidebar = %{sidebar | listeners: [], listeners_loading: false, listeners_error: reason}
    {:noreply, assign(socket, :sidebar, sidebar)}
  end

  def handle_async(:fetch_listeners, {:exit, reason}, socket) do
    sidebar = socket.assigns.sidebar
    sidebar = %{sidebar | listeners: [], listeners_loading: false, listeners_error: reason}
    {:noreply, assign(socket, :sidebar, sidebar)}
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
      <button
        phx-click="close_details"
        class="absolute top-4 right-4 z-10 ghost-icon w-9 h-9 flex items-center justify-center"
      >
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
            listeners={@sidebar.listeners}
            listeners_loading={Map.get(@sidebar, :listeners_loading, false)}
            listeners_error={Map.get(@sidebar, :listeners_error)}
            obfuscated={@obfuscated}
          />
        </div>
      </div>
    </div>
    """
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
          keep_modal_open: schema_modal?,
          data: data
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

  # Attach the machine's overlay IP and (best-effort) WG status for the detail
  # panel. Tolerates mock/unavailable so the UI never crashes.
  defp enrich_overlay(machine) do
    overlay_ip = Tunneld.Overlay.address_for(machine)

    overlay_status =
      case Tunneld.Overlay.status(machine) do
        {:ok, %{up: true}} -> "up"
        {:ok, _} -> "down"
        _ -> nil
      end

    machine
    |> Map.put("overlay_ip", overlay_ip)
    |> Map.put("overlay_status", overlay_status)
    |> Map.put("exit_capable", Tunneld.Egress.exit_capable?(machine))
  end

  # Machines a device can use as an egress (exit) node: any exit-capable
  # managed machine, shown as {id, name}.
  defp egress_machines do
    Tunneld.Machines.list()
    |> Enum.map(fn m -> {m["id"], m["name"] || m["id"]} end)
  end

  # Map-card pins for managed machines (TODO §6). Remote machines plot by
  # geolocating their public IP; local machines pin to the gateway's location.
  # Best-effort: falls back to the gateway location when geolocation fails.
  defp map_nodes do
    gateway = socket_geo_location()

    Tunneld.Machines.list()
    |> Enum.map(fn m ->
      label = m["name"] || m["id"]
      location = m["location"] || "local"
      address = m["address"]
      overlay_ip = Tunneld.Overlay.address_for(m)

      {geo, country} =
        if location == "remote" and is_binary(address) do
          case Tunneld.Geolocation.geolocate(address) do
            {:ok, loc} -> {loc, loc[:country] || loc[:city] || "Remote"}
            _ -> {gateway, "Remote"}
          end
        else
          {gateway, "Local"}
        end

      %{
        latitude: geo[:latitude],
        longitude: geo[:longitude],
        label: label,
        ip: overlay_ip || address || "",
        country: country
      }
    end)
    |> Enum.reject(fn n -> is_nil(n.latitude) or is_nil(n.longitude) end)
  end

  defp socket_geo_location do
    # The gateway's own geolocation, read from the Geolocation service.
    case Tunneld.Geolocation.get_location() do
      {:ok, loc} -> loc
      _ -> %{latitude: 37.7749, longitude: -122.4194}
    end
  end

  defp sanitize_resource_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-zA-Z0-9\-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> String.slice(0, 40)
    |> case do
      "" -> "resource"
      s -> s
    end
  end

  defp sidebar_open(view, selection) when is_atom(view) do
    %{
      is_open: true,
      view: view,
      selection: selection,
      data: nil,
      listeners: [],
      listeners_loading: false,
      listeners_error: nil
    }
  end

  defp open_machine_sidebar(socket, id) do
    case Tunneld.Machines.get(id) do
      {:ok, machine} ->
        machine = enrich_overlay(machine)

        # Open sidebar immediately with machine data, mark listeners as loading
        sidebar = %{
          is_open: true,
          view: :machine,
          selection: %{type: :machine, id: id},
          data: machine,
          listeners: [],
          listeners_loading: true,
          listeners_error: nil
        }

        socket
        |> assign(:sidebar, sidebar)
        |> start_async(:fetch_listeners, fn -> Tunneld.Machines.listeners(id) end)

      _ ->
        assign(socket, :sidebar, @sidebar_default)
    end
  end

  # Refresh only the overlay fields of an open machine sidebar, leaving
  # `listeners` untouched so polling never triggers SSH. A no-op unless a
  # machine panel is actually open.
  defp refresh_sidebar_overlay(socket) do
    sidebar = Map.get(socket.assigns, :sidebar, %{})

    with :machine <- Map.get(sidebar, :view),
         %{type: :machine, id: id} <- Map.get(sidebar, :selection),
         {:ok, machine} <- Tunneld.Machines.get(id) do
      assign(socket, :sidebar, %{sidebar | data: enrich_overlay(machine)})
    else
      _ -> socket
    end
  end

  # After a machine action, re-fetch so the sidebar reflects live state.
  defp maybe_refresh_machine_sidebar(socket, pending) do
    case Map.get(pending, :data, %{}) do
      %{"machine_id" => id} -> refresh_machine_sidebar(socket, id)
      _ -> socket
    end
  end

  defp refresh_machine_sidebar(socket, id) do
    sidebar = Map.get(socket.assigns, :sidebar, %{})

    if Map.get(sidebar, :view) == :machine and
         match?(%{type: :machine, id: ^id}, Map.get(sidebar, :selection)) do
      listeners =
        case Tunneld.Machines.listeners(id) do
          {:ok, l} -> l
          _ -> []
        end

      sidebar = Map.put(sidebar, :listeners, listeners)
      send_update(SidebarDetails, id: "sidebar_details", listeners: listeners)
      assign(socket, :sidebar, sidebar)
    else
      socket
    end
  end

  defp sidebar_close(sidebar) when is_map(sidebar) do
    %{
      is_open: false,
      view: Map.get(sidebar, :view),
      selection: nil,
      data: nil,
      listeners: [],
      listeners_loading: false,
      listeners_error: nil
    }
  end

  defp machine_action_flash(socket, "enroll_machine", %{"public_key" => pub})
       when is_binary(pub) do
    blocks = [
      %{
        "title" => "1. Enable the SSH server (if not already running)",
        "code" =>
          "sudo apt update && sudo apt install -y openssh-server && sudo systemctl enable --now ssh"
      },
      %{
        "title" => "2. Install the SSH key on the target",
        "code" =>
          "mkdir -p ~/.ssh && echo '#{String.trim(pub)}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
      },
      %{
        "title" => "3. (Remote machines) Open the WireGuard port in the provider firewall",
        "code" =>
          "Allow inbound UDP/51821 in the target's cloud-provider firewall (e.g. a Vultr security group) so the gateway can bring up the WireGuard overlay."
      }
    ]

    modal = %{
      show: true,
      title: "Machine enrolled",
      description:
        "Run these on the target so tunneld can connect over SSH, discover what is listening, and (for remote machines) bring it onto the WireGuard overlay.",
      body: %{"type" => "code_blocks", "data" => blocks},
      actions: nil,
      type: :default
    }

    assign(socket, :modal, Map.merge(socket.assigns.modal, modal))
  end

  defp machine_action_flash(socket, "enroll_machine", %{"machine" => %{"name" => name}}) do
    put_flash(
      socket,
      :info,
      "Machine #{name} enrolled. You can now install its key and probe it."
    )
  end

  defp machine_action_flash(socket, _action, _result), do: socket

  # start_action wraps perform/3 as {:ok, perform(...)}. perform/3 itself returns
  # {:ok, data} | {:error, reason} for machine actions, so we unwrap both layers.
  defp unwrap_result({:ok, {:ok, data}}), do: {:ok, data}
  defp unwrap_result({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_result({:ok, data}), do: {:ok, data}
  defp unwrap_result({:error, reason}), do: {:error, reason}
  defp unwrap_result(other), do: {:ok, other}

  defp machine_error("enroll_machine", reason), do: "enrollment failed: #{error_message(reason)}"

  defp machine_error(_action, reason), do: error_message(reason)

  # One formatter for both flash copy and logs. Users must never see a raw
  # Elixir term, and a readable sentence carrying the exit code plus ssh's own
  # stderr is more useful in the log than a nested tuple anyway.
  defp error_message({:ssh_failed, code, out}), do: "SSH exited #{code}: #{first_line(out)}"
  defp error_message({:ssh_failed, out}), do: "SSH failed: #{first_line(out)}"
  defp error_message(reason) when is_binary(reason), do: first_line(reason)
  defp error_message(:timeout), do: "the machine did not respond in time"
  defp error_message(reason) when is_atom(reason), do: to_string(reason)
  defp error_message(%{__exception__: true} = e), do: first_line(Exception.message(e))
  defp error_message({kind, _reason}) when is_atom(kind), do: "unexpected #{kind} failure"
  defp error_message(_), do: "unexpected failure"

  defp first_line(text) when is_binary(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.first()
    |> case do
      nil -> "no details reported"
      line -> String.slice(line, 0, 120)
    end
  end

  defp first_line(_), do: "no details reported"

  defp format_exit_result({:ok, %{iface: iface}}, label),
    do: "#{label} is now exit-capable (IP forwarding + NAT on #{iface})"

  defp format_exit_result({:ok, _}, label), do: "#{label} is now exit-capable"

  defp format_exit_result({:error, :no_default_route_on_target}, label),
    do: "Exit setup failed: #{label} has no default route, so there is no interface to NAT out of"

  defp format_exit_result({:error, reason}, label) when is_binary(reason),
    do: "Exit setup failed for #{label}: #{reason}"

  defp format_exit_result({:error, {:ssh_failed, code, out}}, label),
    do: "Exit setup failed for #{label}: SSH exited #{code}: #{first_line(out)}"

  defp format_exit_result({:error, reason}, label),
    do: "Exit setup failed for #{label}: #{inspect(reason)}"

  # An unrecognised shape means we do not know whether the exit is configured.
  # The previous catch-all rendered exactly this case as "Exit node configured
  # for <uuid>" - a success sentence, quoting an internal id, for a result we
  # could not classify. Unknown is reported as unknown.
  defp format_exit_result(other, label) do
    require Logger
    Logger.warning("Unexpected ensure_exit_capable result: #{inspect(other)}")
    "Exit setup for #{label} returned an unrecognised result - verify from the machine panel"
  end

  defp format_reconcile_result(%{error: reason}), do: "Reconcile failed: #{reason}"

  # Name the parts that did not work. "Reconcile complete" over a failed
  # overlay is the same lie as an error toast over a working exit node.
  defp format_reconcile_result(%{overlay: overlay, exit: exit_result}) do
    failed =
      [{"overlay", overlay}, {"exit routing", exit_result}]
      |> Enum.reject(fn {_name, res} -> match?({:ok, _}, res) or res in [:ok, :skipped] end)
      |> Enum.map(&elem(&1, 0))

    case failed do
      [] -> "Sync complete: overlay up, exit routing applied"
      names -> "Sync finished with problems: #{Enum.join(names, " and ")} failed"
    end
  end

  defp format_reconcile_result(_), do: "Sync complete"
end

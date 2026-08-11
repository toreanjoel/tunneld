defmodule TunneldWeb.Live.Components.Sidebar.Details do
  @moduledoc """
  The list of sidebar details to render.

  Renders one of several views selected by the parent LiveView:

  - `:system_overview` - default "all good" panel
  - `:resource`        - a single resource's details and actions
  - `:machine`         - a single managed machine's details and listeners
  - `:ethernet`        - upstream/downstream interface link state
  - `:dns_server`      - upstream DNS server configuration
  - `:authentication`  - login reset
  - `:service`         - system service logs and restart
  """

  use TunneldWeb, :live_component
  import TunneldWeb.Live.Components.HelpIcon

  def mount(socket) do
    {:ok,
     assign(socket,
       listeners_expanded: false,
       listeners_loading: false,
       listeners_error: nil,
       show_infra: false
     )}
  end

  def update(assigns, socket) do
    view = Map.get(assigns, :view, socket.assigns[:view] || :system_overview)
    data = Map.get(assigns, :data, %{})
    listeners = Map.get(assigns, :listeners, socket.assigns[:listeners] || [])

    listeners_loading =
      Map.get(assigns, :listeners_loading, socket.assigns[:listeners_loading] || false)

    listeners_error = Map.get(assigns, :listeners_error, socket.assigns[:listeners_error])
    selection = Map.get(assigns, :selection, socket.assigns[:selection] || nil)
    obfuscated = Map.get(assigns, :obfuscated, false)

    socket =
      socket
      |> assign_new(:obfuscated, fn -> false end)
      |> assign(:view, view)
      |> assign(:data, data)
      |> assign(:listeners, listeners)
      |> assign(:listeners_loading, listeners_loading)
      |> assign(:listeners_error, listeners_error)
      |> assign(:selection, selection)
      |> assign(:obfuscated, obfuscated)

    {:ok, socket}
  end

  def handle_event("toggle_listeners", _params, socket) do
    {:noreply, assign(socket, :listeners_expanded, !socket.assigns.listeners_expanded)}
  end

  def handle_event("toggle_infra", _params, socket) do
    {:noreply, assign(socket, :show_infra, !socket.assigns.show_infra)}
  end

  @spec render(%{:view => :system_overview, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  def render(%{view: :system_overview} = assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center p-5 h-full">
      <.icon class="w-[50px] h-[50px] text-green" name="hero-shield-check" />
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">System is running as expected.</h1>
    </div>
    """
  end

  @spec render(%{:view => :authentication, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  def render(%{view: :authentication} = assigns) do
    ~H"""
    <div class="p-4 space-y-6 min-h-full">
      <%= sidebar_header(assigns, %{
        header: "Authentication",
        body: "Reset your login credentials for the dashboard."
      }) %>

      <div class="flex flex-row gap-1 justify-end my-2">
        <div
          phx-click="modal_open"
          phx-value-modal_title="Reset Login?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" =>
                "This will reset your login details. New details will be prompted for and required on your next login"
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Reset",
              "payload" => %{
                "type" => "revoke_login_creds",
                "data" => %{}
              }
            })
          }
          phx-click-loading="opacity-50 cursor-wait"
          class="flex grow items-center justify-center gap-1 bg-red p-2 cursor-pointer rounded-md w-full"
        >
          <.icon name="hero-no-symbol" class="h-5 w-5" />
          <div class="truncate text-xs">Reset Login</div>
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :resource, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :resource} = assigns) do
    data = Map.get(assigns, :data)

    assigns =
      assigns
      |> assign(has_data: is_map(data) and map_size(data) > 0)
      |> assign(gateway: Application.get_env(:tunneld, :network)[:gateway])
      |> assign(data: data)
      |> assign(health: Map.get(data || %{}, :health) || Map.get(data || %{}, "health") || %{})

    ~H"""
    <div class="p-4 space-y-6 min-h-full">
      <div :if={@has_data}>
        <%= sidebar_header(assigns, %{
          header: mask(@obfuscated, @data.name),
          body:
            @data.description ||
              "A reference to a running service accessible from this device over the network. Tracks availability and load-balances its backend pool."
        }) %>
      </div>

      <div :if={@has_data} class="flex flex-row gap-1 justify-end my-2">
        <% resource_schema =
          Tunneld.Schema.Resource.data(:add_public)
          |> Map.put("ui:order", ["id", "name", "description", "pool", "ip", "port"])
          |> put_in(["properties", "id"], %{
            "type" => "string",
            "ui:widget" => "hidden",
            "readOnly" => true
          })
          |> put_in(["properties", "name", "readOnly"], true) %>

        <div
          :if={@data.kind == "host"}
          phx-click="modal_open"
          phx-value-modal_title="Edit Resource"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => resource_schema,
              "default_values" => %{
                "id" => @data.id,
                "name" => @data.name,
                "description" => @data.description,
                "pool" => @data.pool || [],
                "ip" => @data.ip,
                "port" => @data.port
              },
              "action" => "update_share"
            })
          }
          phx-click-loading="opacity-50 cursor-wait"
          class="flex items-center justify-center gap-1 w-full bg-surface p-2 cursor-pointer rounded-md hover:bg-surface-2"
        >
          <.icon name="hero-pencil-square" class="h-5 w-5" />
          <div class="truncate text-xs">Edit</div>
        </div>

        <div
          phx-click="modal_open"
          phx-value-modal_title="Remove Resource?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" => "Are you sure you want to remove the resource?"
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Remove",
              "payload" => %{
                "type" => "remove_share",
                "data" => %{"id" => @data.id, "kind" => @data.kind}
              }
            })
          }
          phx-click-loading="opacity-50 cursor-wait"
          class="flex items-center justify-center gap-1 w-full bg-red p-2 cursor-pointer rounded-md hover:opacity-80"
        >
          <.icon name="hero-no-symbol" class="h-5 w-5" />
          <div class="truncate text-xs">Remove Resource</div>
        </div>
      </div>

      <div class={"flex flex-col #{if !@has_data, do: "items-center justify-center p-3 h-full", else: ""}"}>
        <h1 :if={!@has_data} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Resource details
        </h1>

        <div :if={@has_data}>
          <div class="flex flex-col p-3 mb-2 bg-surface rounded-lg font-light">
            <div class="text-sm truncate">
              <span class="font-bold">Name:</span>
              <%= mask(@obfuscated, @data.name) %>
            </div>
            <% health = Map.get(@data, :health) || Map.get(@data, "health") || %{} %>
            <div class="text-sm truncate">
              <span class="font-bold">Health:</span>
              <span class={"ml-1 w-[13px] h-[13px] rounded-full inline-block align-middle #{pool_health_dot(health[:status])}"}>
              </span>
              <span class="ml-1 capitalize"><%= human_health(health[:status]) %></span>
              <%= if is_number(health[:up]) and is_number(health[:total]) do %>
                <span class="ml-1 text-xs text-gray-300">
                  (<%= health[:up] %>/<%= health[:total] %> up)
                </span>
              <% end %>
            </div>
            <div :if={@data[:lan_url]} class="text-sm truncate">
              <span class="font-bold">LAN URL:</span>
              <span class="ml-1 font-mono text-xs"><%= @data[:lan_url] %></span>
            </div>
            <div :if={@data[:loopback_port]} class="text-sm truncate">
              <span class="font-bold">Manual exposure:</span>
              <span class="ml-1 font-mono text-xs">
                <%= Tunneld.Caddy.gateway_ip() || "127.0.0.1" %>:<%= @data[:loopback_port] %>
              </span>
              <span class="ml-1 text-xs text-gray-400">
                (point zrok/cloudflared here from any subnet machine)
              </span>
            </div>
          </div>

          <% pool_details = Map.get(@data, :pool_details, []) %>

          <%= if @data.kind == "host" and @has_data do %>
            <div class="mt-3 border-t border-gray-700 pt-3">
              <div class="flex items-center justify-between mb-2">
                <h2 class="text-sm font-semibold">Pool Backends</h2>
                <button
                  phx-click="add_pool_member_modal"
                  phx-value-id={@data.id}
                  class="ghost-btn !px-2 !py-0.5 text-[10px]"
                >
                  + Add backend
                </button>
              </div>
              <div class="bg-surface rounded-lg p-2 space-y-1.5">
                <%= if Enum.empty?(pool_details) do %>
                  <div class="text-xs text-gray-400">No backends configured</div>
                <% else %>
                  <%= for {entry, up?} <- pool_details do %>
                    <div class="flex items-center gap-2">
                      <span class={"w-2 h-2 rounded-full inline-block #{if up?, do: "bg-green", else: "bg-yellow"}"}>
                      </span>
                      <span class="font-mono text-xs text-gray-300">
                        <%= mask(@obfuscated, entry) %>
                      </span>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :machine, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  def render(%{view: :machine} = assigns) do
    machine = Map.get(assigns, :data, %{})
    all_listeners = Map.get(assigns, :listeners, [])

    # The operator asked not to see sshd/caddy/resolved by default. Split rather
    # than discard: infrastructure stays one click away behind the toggle.
    {infra, app} = Enum.split_with(all_listeners, & &1["infrastructure"])
    visible = if Map.get(assigns, :show_infra, false), do: all_listeners, else: app

    assigns =
      assigns
      |> assign(:machine, machine)
      |> assign(:listeners, all_listeners)
      |> assign(:visible_listeners, visible)
      |> assign(:infra_count, length(infra))

    ~H"""
    <div class="p-4 space-y-5 min-h-full">
      <%= if @machine == %{} do %>
        <div class="flex flex-col items-center justify-center p-5 h-full">
          <h1 class="text-2xl font-light text-gray-2 my-4 text-center">Machine not found</h1>
        </div>
      <% else %>
        <%= sidebar_header(assigns, %{
          header: mask(@obfuscated, mget(@machine, "name")),
          body:
            "#{mget(@machine, "address")} · #{mget(@machine, "kind")} · #{location_label(mget(@machine, "location"))}"
        }) %>

        <div class="grid grid-cols-2 gap-1.5 my-2 items-stretch">
          <div
            phx-click="reconcile_machine"
            phx-value-id={mget(@machine, "id")}
            phx-click-loading="opacity-50 cursor-wait"
            class="flex items-center justify-center gap-1.5 w-full h-9 bg-surface p-2 cursor-pointer rounded-md hover:bg-surface-2"
          >
            <.icon name="hero-arrow-path" class="h-4 w-4 shrink-0" />
            <div class="truncate text-xs">Reconcile</div>
            <.help_icon
              class="ml-0.5"
              text="Sync this machine: ensure the WireGuard overlay is up, re-apply exit routing, re-probe its OS/runtimes/listeners, and check for drift."
            />
          </div>

          <div
            phx-click="make_exit_node"
            phx-value-id={mget(@machine, "id")}
            phx-click-loading="opacity-50 cursor-wait"
            class={"flex items-center justify-center gap-1.5 w-full h-9 p-2 cursor-pointer rounded-md #{if @machine["exit_capable"], do: "bg-accent/20 text-accent hover:bg-accent/30", else: "bg-surface hover:bg-surface-2"}"}
          >
            <.icon name="hero-arrow-up-tray" class="h-4 w-4 shrink-0" />
            <div class="truncate text-xs">Exit Node</div>
            <.help_icon
              class="ml-0.5"
              text="Re-apply exit routing on this machine (IP forwarding + NAT). Enrolling already does this; use it to repair after the machine reboots, since its iptables rules are not persistent. Route specific devices through it from the Devices list."
            />
          </div>

          <div
            phx-click="view_ssh_key"
            phx-value-id={mget(@machine, "id")}
            class="flex items-center justify-center gap-1.5 w-full h-9 bg-surface p-2 cursor-pointer rounded-md hover:bg-surface-2"
          >
            <.icon name="hero-key" class="h-4 w-4 shrink-0" />
            <div class="truncate text-xs">SSH Key</div>
          </div>

          <div
            phx-click="open_terminal"
            phx-value-id={mget(@machine, "id")}
            class="flex items-center justify-center gap-1.5 w-full h-9 bg-accent p-2 cursor-pointer rounded-md hover:bg-accent-light"
            title="Open an interactive terminal to this machine"
          >
            <.icon name="hero-command-line" class="h-4 w-4 shrink-0" />
            <div class="truncate text-xs">Terminal</div>
          </div>

          <div
            phx-click="remove_machine"
            phx-value-id={mget(@machine, "id")}
            class="flex items-center justify-center gap-1.5 w-full h-9 bg-red p-2 cursor-pointer rounded-md hover:opacity-80 col-span-2"
          >
            <.icon name="hero-trash" class="h-4 w-4 shrink-0" />
            <div class="truncate text-xs">Remove</div>
          </div>
        </div>

        <div class="flex flex-col p-3 mb-1 bg-surface rounded-lg font-light space-y-1.5">
          <div class="flex items-center justify-between text-sm">
            <span class="text-text-tertiary">Status</span>
            <span class="flex items-center gap-1.5 capitalize">
              <span class={"w-[10px] h-[10px] rounded-full inline-block #{status_dot(mget(@machine, "status"))}"}>
              </span>
              <%= mget(@machine, "status") %>
            </span>
          </div>
          <%= if caps = mget(@machine, "capabilities") do %>
            <div class="flex items-center justify-between text-sm gap-3">
              <span class="text-text-tertiary shrink-0">OS</span>
              <span class="truncate text-right"><%= caps["os"] %></span>
            </div>
            <div class="flex items-center justify-between text-sm">
              <span class="text-text-tertiary">CPU</span>
              <span><%= caps["cpu_count"] %></span>
            </div>
            <div class="flex items-center justify-between text-sm">
              <span class="text-text-tertiary">RAM</span>
              <span><%= caps["memory_mb"] %> MB</span>
            </div>
          <% end %>
          <%= if mget(@machine, "overlay_ip") do %>
            <div class="flex items-center justify-between text-sm">
              <span class="text-text-tertiary">Overlay</span>
              <span class="font-mono text-xs text-accent"><%= mget(@machine, "overlay_ip") %></span>
            </div>
          <% end %>
          <%= if mget(@machine, "overlay_status") do %>
            <div class="flex items-center justify-between text-sm">
              <span class="text-text-tertiary">WireGuard</span>
              <span class="capitalize"><%= mget(@machine, "overlay_status") %></span>
            </div>
          <% end %>
          <div class="flex items-center justify-between text-sm">
            <span class="text-text-tertiary">Exit</span>
            <span class="flex items-center gap-1.5 capitalize">
              <span class={"w-[10px] h-[10px] rounded-full inline-block #{if mget(@machine, "exit_capable"), do: "bg-emerald-500", else: "bg-gray-500"}"}>
              </span>
              <%= if mget(@machine, "exit_capable"), do: "capable", else: "not set" %>
            </span>
          </div>
          <%= if mget(@machine, "last_seen") do %>
            <div class="flex items-center justify-between text-sm">
              <span class="text-text-tertiary">Last seen</span>
              <span class="text-gray-400">
                <%= String.slice(mget(@machine, "last_seen"), 0, 19) %>
              </span>
            </div>
          <% end %>
        </div>

        <div class="mt-4">
          <div class="flex items-center justify-between mb-2">
            <div class="text-sm font-semibold">Listeners</div>
            <div class="flex items-center gap-1">
              <button
                :if={not @listeners_loading and @infra_count > 0}
                phx-click="toggle_infra"
                phx-target={@myself}
                class="ghost-btn !px-2 !py-0.5 text-[10px]"
                title="Infrastructure services (sshd, caddy, resolved and friends) are hidden by default"
              >
                <%= if @show_infra,
                  do: "hide infrastructure",
                  else: "show infrastructure (#{@infra_count})" %>
              </button>
              <button
                :if={not @listeners_loading}
                phx-click="toggle_listeners"
                phx-target={@myself}
                class="ghost-btn !px-2 !py-0.5 text-[10px]"
              >
                <%= if @listeners_expanded,
                  do: "Hide",
                  else: "Show #{length(@visible_listeners)}" %>
              </button>
            </div>
          </div>
          <%= if @listeners_loading do %>
            <div class="flex items-center gap-2 text-xs text-gray-400" role="status">
              <svg
                class="animate-spin h-4 w-4 text-accent"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                >
                </circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                >
                </path>
              </svg>
              <span>Loading listeners...</span>
            </div>
          <% else %>
            <%= if @listeners_error do %>
              <div class="text-xs text-red italic">
                Could not read listeners — <%= listener_error_message(@listeners_error) %>
              </div>
            <% else %>
              <%= if Enum.empty?(@visible_listeners) do %>
                <div class="text-xs text-gray-400 italic">
                  <%= if @infra_count > 0 do %>
                    No app listeners — <%= @infra_count %> infrastructure <%= if @infra_count == 1,
                      do: "service is",
                      else: "services are" %> hidden.
                  <% else %>
                    No listeners discovered
                  <% end %>
                </div>
              <% else %>
                <%= if @listeners_expanded do %>
                  <div class="space-y-1">
                    <%= for l <- @visible_listeners do %>
                      <div class="bg-surface rounded p-2 text-xs flex items-center justify-between">
                        <div class="flex items-center gap-2 min-w-0">
                          <span class={"w-2 h-2 rounded-full shrink-0 #{if l["infrastructure"], do: "bg-gray-500", else: "bg-green"}"}>
                          </span>
                          <span class="font-mono truncate"><%= l["addr"] %>:<%= l["port"] %></span>
                          <span class="text-gray-400 truncate">
                            <%= l["proc"] %> (<%= l["pid"] %>)
                          </span>
                          <span
                            :if={l["infrastructure"]}
                            class="px-1.5 py-0.5 rounded-full bg-text-primary/10 text-text-tertiary text-[9px] shrink-0"
                          >
                            infra
                          </span>
                          <span
                            :if={l["loopback"]}
                            class="px-1.5 py-0.5 rounded-full bg-text-primary/10 text-text-tertiary text-[9px] shrink-0"
                            title="Bound to loopback only - not reachable from the LAN"
                          >
                            loopback
                          </span>
                          <span :if={l["container"]} class="text-accent truncate">
                            · <%= l["container"] %>
                          </span>
                        </div>
                        <button
                          :if={not l["loopback"]}
                          phx-click="make_listener_resource"
                          phx-value-machine_id={mget(@machine, "id")}
                          phx-value-addr={l["addr"]}
                          phx-value-port={l["port"]}
                          phx-value-proc={l["proc"]}
                          class="ghost-btn !px-2 !py-0.5 text-[10px] shrink-0"
                        >
                          make resource
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <div class="text-xs text-gray-400 italic">
                    Collapsed — click Show to see listening processes.
                  </div>
                <% end %>
              <% end %>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @spec render(%{:view => :ethernet, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  def render(%{view: :ethernet} = assigns) do
    status = Tunneld.NetLink.status()

    assigns =
      assigns
      |> assign(upstream: status.upstream)
      |> assign(downstream: status.downstream)

    ~H"""
    <div class="p-4 space-y-6 min-h-full">
      <%= sidebar_header(assigns, %{
        header: "Network Interfaces",
        body: "Upstream and downstream ethernet link state for this gateway."
      }) %>

      <div class="space-y-3">
        <div class="bg-surface rounded-lg p-3 flex items-center justify-between">
          <div class="flex flex-col">
            <span class="text-sm font-semibold">Upstream</span>
            <span class="text-xs text-gray-400 font-mono"><%= @upstream.iface || "—" %></span>
          </div>
          <div class="flex items-center gap-2">
            <span class={"w-3 h-3 rounded-full inline-block #{if @upstream.up, do: "bg-green", else: "bg-red"}"} />
            <span class="text-xs capitalize"><%= if @upstream.up, do: "up", else: "down" %></span>
          </div>
        </div>

        <div class="bg-surface rounded-lg p-3 flex items-center justify-between">
          <div class="flex flex-col">
            <span class="text-sm font-semibold">Downstream</span>
            <span class="text-xs text-gray-400 font-mono"><%= @downstream.iface || "—" %></span>
          </div>
          <div class="flex items-center gap-2">
            <span class={"w-3 h-3 rounded-full inline-block #{if @downstream.up, do: "bg-green", else: "bg-red"}"} />
            <span class="text-xs capitalize"><%= if @downstream.up, do: "up", else: "down" %></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :dns_server, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :dns_server} = assigns) do
    dns_server = Tunneld.Servers.DnsConfig.get_dns_server()

    assigns =
      assigns
      |> assign(dns_server: dns_server)

    ~H"""
    <div class="p-4 space-y-6 min-h-full">
      <%= sidebar_header(assigns, %{
        header: "DNS Server",
        body:
          "All DNS queries on the subnet are forwarded to this server. Use a public resolver like 1.1.1.1 or a local Pi-hole on your network."
      }) %>

      <div class="bg-surface rounded-lg p-3 space-y-3">
        <div class="text-xs text-gray-400">
          Current DNS server: <span class="text-text-secondary font-mono"><%= @dns_server %></span>
        </div>

        <div
          phx-click="modal_open"
          phx-value-modal_title="Set DNS Server"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Tunneld.Schema.data(:dns_server),
              "default_values" => %{"server" => @dns_server},
              "action" => "set_dns_server"
            })
          }
          phx-click-loading="opacity-50 cursor-wait"
          class="flex items-center justify-center gap-1 bg-accent hover:bg-accent-light p-2 cursor-pointer rounded-md transition-all duration-150 text-xs text-white"
        >
          <.icon class="w-4 h-4" name="hero-pencil-square" /> Change DNS Server
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :service, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :service} = assigns) do
    data = Map.get(assigns, :data)
    logs = Map.get(data, :logs, [])
    count = length(logs)

    service =
      case service = Map.get(data, :service) do
        :dnsmasq ->
          %{
            id: service,
            name: service |> Atom.to_string() |> String.capitalize(),
            description: "Lightweight DNS/DHCP daemon handling local name resolution and leases."
          }

        :dhcpcd ->
          %{
            id: service,
            name: service |> Atom.to_string() |> String.capitalize(),
            description:
              "Client daemon that manages the upstream network lease and interface config"
          }

        :caddy ->
          %{
            id: service,
            name: service |> Atom.to_string() |> String.capitalize(),
            description:
              "Reverse proxy/load balancer (Caddy) that fronts your exposed resources and distributes traffic."
          }

        # This is needed so when the component updates, we have some default value
        _ ->
          %{
            id: "-",
            name: "-",
            description: "-"
          }
      end

    assigns =
      assigns
      |> assign(logs: logs)
      |> assign(count: count)
      |> assign(service: service)

    ~H"""
    <div class="p-4 space-y-6 min-h-full">
      <%!-- Sidebar header that will house metadat?  --%>
      <%= sidebar_header(assigns, %{
        header: Map.get(@service, :name),
        body: Map.get(@service, :description)
      }) %>

      <div class="flex flex-row gap-1 justify-end my-2">
        <%!-- Actions to take --%>
        <div
          phx-click="trigger_action"
          phx-value-action="refresh_service_logs"
          phx-value-data={Jason.encode!(%{"id" => Map.get(@service, :id)})}
          phx-click-loading="opacity-50 cursor-wait"
          class="flex items-center justify-center gap-1 w-full bg-surface p-2 cursor-pointer rounded-md hover:bg-surface-2"
        >
          <.icon class="w-4 h-4" name="hero-arrow-path" />
          <div class="truncate text-xs text-text-secondary">Refresh</div>
        </div>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Restart Service?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" => "Are you sure you want to restart the service?"
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Restart",
              "payload" => %{
                "type" => "restart_service",
                "data" => %{"id" => Map.get(@service, :id)}
              }
            })
          }
          phx-click-loading="opacity-50 cursor-wait"
          class="flex items-center justify-center gap-1 bg-accent p-2 cursor-pointer rounded-md"
        >
          <.icon name="hero-arrow-path" class="h-4 w-4" />
          <div class="truncate text-xs">Restart Service</div>
        </div>
      </div>

      <div class={"flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Service Logs
        </h1>

        <div :if={@count > 0}>
          <%= for log <- @logs do %>
            <div class="flex flex-col p-3 mb-2 bg-surface rounded-lg font-light">
              <div class="text-sm"><%= log %></div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # User-facing copy: never render a raw Elixir term. Keep the diagnostic detail
  # (exit code, ssh's own stderr) but as a readable sentence.
  defp listener_error_message({:ssh_failed, code, out}) do
    "SSH exited #{code}: #{first_line(out)}"
  end

  defp listener_error_message({:ssh_failed, out}), do: "SSH failed: #{first_line(out)}"
  defp listener_error_message(reason) when is_binary(reason), do: first_line(reason)
  defp listener_error_message(:timeout), do: "the machine did not respond in time"
  defp listener_error_message(reason) when is_atom(reason), do: to_string(reason)

  defp listener_error_message(%{message: message}) when is_binary(message),
    do: first_line(message)

  defp listener_error_message(_), do: "the machine could not be reached"

  # ssh dumps multi-line stderr; the first non-empty line is the useful part.
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

  defp human_health(:all_up), do: "healthy"
  defp human_health(:none), do: "down"
  defp human_health(:partial), do: "degraded"
  defp human_health(:mock), do: "mock"
  defp human_health(:empty), do: "no backends"
  defp human_health(:not_applicable), do: "n/a"
  defp human_health(_), do: "unknown"

  defp pool_health_dot(:all_up), do: "bg-green"
  defp pool_health_dot(:none), do: "bg-red"
  defp pool_health_dot(:partial), do: "bg-yellow"
  defp pool_health_dot(_), do: "bg-gray-500"

  defp status_dot("ready"), do: "bg-green"
  defp status_dot("enrolled"), do: "bg-yellow"
  defp status_dot("probing"), do: "bg-yellow"
  defp status_dot("unreachable"), do: "bg-red"
  defp status_dot(_), do: "bg-gray-500"

  defp location_label("remote"), do: "remote"
  defp location_label(_), do: "local"

  defp sidebar_header(assigns, %{header: header, body: body}) do
    assigns =
      assigns
      |> assign(header: header)
      |> assign(body: body)

    ~H"""
    <div class="bg-surface-2 bg-gradient-to-r from-surface-2 to-surface rounded-md p-3">
      <div class="text-xl font-medium"><%= @header %></div>
      <div class="text-sm">
        <%= @body %>
      </div>
    </div>
    """
  end

  defp mget(machine, key) when is_binary(key) do
    case Map.get(machine, key) do
      nil -> Map.get(machine, String.to_atom(key))
      val -> val
    end
  end
end

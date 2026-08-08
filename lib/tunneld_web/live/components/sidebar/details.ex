defmodule TunneldWeb.Live.Components.Sidebar.Details do
  @moduledoc """
  The list of sidebar details to render.

  Renders one of several views selected by the parent LiveView:

  - `:system_overview` - default "all good" panel
  - `:resource`        - a single resource's details and actions
  - `:machine`         - a single managed machine's details and containers
  - `:ethernet`        - upstream/downstream interface link state
  - `:dns_server`      - upstream DNS server configuration
  - `:authentication`  - login reset
  - `:service`         - system service logs and restart
  """

  use TunneldWeb, :live_component

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    view = Map.get(assigns, :view, socket.assigns[:view] || :system_overview)
    data = Map.get(assigns, :data, %{})
    containers = Map.get(assigns, :containers, [])
    listeners = Map.get(assigns, :listeners, socket.assigns[:listeners] || [])
    selection = Map.get(assigns, :selection, socket.assigns[:selection] || nil)
    obfuscated = Map.get(assigns, :obfuscated, false)

    socket =
      socket
      |> assign_new(:obfuscated, fn -> false end)
      |> assign(:view, view)
      |> assign(:data, data)
      |> assign(:containers, containers)
      |> assign(:listeners, listeners)
      |> assign(:selection, selection)
      |> assign(:obfuscated, obfuscated)

    {:ok, socket}
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
              <span class="font-bold">Loopback:</span>
              <span class="ml-1 font-mono text-xs">127.0.0.1:<%= @data[:loopback_port] %></span>
              <span class="ml-1 text-xs text-gray-400">(manual exposure via zrok/cloudflared)</span>
            </div>
          </div>

          <% pool_details = Map.get(@data, :pool_details, []) %>

          <%= if @data.kind == "host" and @has_data do %>
            <div class="mt-3 border-t border-gray-700 pt-3">
              <h2 class="text-sm font-semibold mb-2">Pool Backends</h2>
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
    containers = Map.get(assigns, :containers, [])

    assigns =
      assigns
      |> assign(:machine, machine)
      |> assign(:containers, containers)
      |> assign(:listeners, Map.get(assigns, :listeners, []))

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

        <div class="grid grid-cols-2 gap-1 my-2">
          <div
            phx-click="probe_machine"
            phx-value-id={mget(@machine, "id")}
            phx-click-loading="opacity-50 cursor-wait"
            class="flex items-center justify-center gap-1 w-full bg-surface p-2 cursor-pointer rounded-md hover:bg-surface-2"
          >
            <.icon name="hero-arrow-path" class="h-5 w-5" />
            <div class="truncate text-xs">Probe</div>
          </div>

          <div
            phx-click="view_ssh_key"
            phx-value-id={mget(@machine, "id")}
            class="flex items-center justify-center gap-1 w-full bg-surface p-2 cursor-pointer rounded-md hover:bg-surface-2"
          >
            <.icon name="hero-key" class="h-5 w-5" />
            <div class="truncate text-xs">SSH Key</div>
          </div>

          <div
            phx-click="install_incus"
            phx-value-id={mget(@machine, "id")}
            phx-click-loading="opacity-50 cursor-wait"
            class="flex items-center justify-center gap-1 w-full bg-surface p-2 cursor-pointer rounded-md hover:bg-surface-2"
          >
            <.icon name="hero-cog-6-tooth" class="h-5 w-5" />
            <div class="truncate text-xs">Install Incus</div>
          </div>

          <div
            phx-click="create_container_modal"
            phx-value-id={mget(@machine, "id")}
            class="flex items-center justify-center gap-1 w-full bg-surface p-2 cursor-pointer rounded-md hover:bg-surface-2"
          >
            <.icon name="hero-plus-circle" class="h-5 w-5" />
            <div class="truncate text-xs">New Container</div>
          </div>

          <div
            phx-click="remove_machine"
            phx-value-id={mget(@machine, "id")}
            class="flex items-center justify-center gap-1 w-full bg-red p-2 cursor-pointer rounded-md hover:opacity-80"
          >
            <.icon name="hero-trash" class="h-5 w-5" />
            <div class="truncate text-xs">Remove</div>
          </div>
        </div>

        <div class="flex flex-col p-3 mb-1 bg-surface rounded-lg font-light space-y-1">
          <div class="text-sm truncate">
            <span class="font-bold">Status:</span>
            <span class={"ml-1 w-[13px] h-[13px] rounded-full inline-block align-middle #{status_dot(mget(@machine, "status"))}"}>
            </span>
            <span class="ml-1 capitalize"><%= mget(@machine, "status") %></span>
          </div>
          <%= if mget(@machine, "capabilities") do %>
            <% caps = mget(@machine, "capabilities") %>
            <div class="text-sm truncate">
              <span class="font-bold">Incus:</span> <%= caps["incus_version"] %>
            </div>
            <div class="text-sm truncate"><span class="font-bold">OS:</span> <%= caps["os"] %></div>
            <div class="text-sm truncate">
              <span class="font-bold">CPU:</span> <%= caps["cpu_count"] %>
            </div>
            <div class="text-sm truncate">
              <span class="font-bold">RAM:</span> <%= caps["memory_mb"] %> MB
            </div>
            <div class="text-sm truncate"><span class="font-bold">KVM:</span> <%= caps["kvm"] %></div>
            <div class="text-sm truncate"><span class="font-bold">GPU:</span> <%= caps["gpu"] %></div>
          <% end %>
          <%= if mget(@machine, "last_seen") do %>
            <div class="text-sm truncate text-gray-400">
              last seen <%= String.slice(mget(@machine, "last_seen"), 0, 19) %>
            </div>
          <% end %>
        </div>

        <div class="mt-4">
          <div class="text-sm font-semibold mb-2">Listeners</div>
          <%= if Enum.empty?(@listeners) do %>
            <div class="text-xs text-gray-400 italic">No listeners discovered</div>
          <% else %>
            <div class="space-y-1">
              <%= for l <- @listeners do %>
                <div class="bg-surface rounded p-2 text-xs flex items-center justify-between">
                  <div class="flex items-center gap-2 min-w-0">
                    <span class="w-2 h-2 rounded-full bg-green shrink-0"></span>
                    <span class="font-mono truncate"><%= l["addr"] %>:<%= l["port"] %></span>
                    <span class="text-gray-400 truncate"><%= l["proc"] %> (<%= l["pid"] %>)</span>
                    <span :if={l["container"]} class="text-accent truncate">· <%= l["container"] %></span>
                  </div>
                  <button
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
          <% end %>
        </div>

        <div>
          <div class="text-sm font-semibold mb-2">Containers</div>
          <%= if Enum.empty?(@containers) do %>
            <div class="text-xs text-gray-400 italic">No containers</div>
          <% else %>
            <div class="space-y-1">
              <%= for c <- @containers do %>
                <div class="bg-surface rounded p-2 text-xs">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-2 min-w-0">
                      <span class={"w-2 h-2 rounded-full inline-block align-middle shrink-0 #{container_dot(c["status"])}"}>
                      </span>
                      <span class="font-mono truncate"><%= c["name"] %></span>
                      <span class="text-gray-400"><%= c["type"] %></span>
                      <%= if c["ipv4"] != "" and c["ipv4"] != nil do %>
                        <span class="text-gray-400 truncate">· <%= c["ipv4"] %></span>
                      <% end %>
                    </div>
                    <div class="flex gap-1 shrink-0">
                      <button
                        phx-click="open_terminal"
                        phx-value-id={mget(@machine, "id")}
                        phx-value-name={c["name"]}
                        class="ghost-btn !px-2 !py-0.5 text-[10px]"
                      >
                        shell
                      </button>
                      <button
                        phx-click="start_container"
                        phx-value-id={mget(@machine, "id")}
                        phx-value-name={c["name"]}
                        class="ghost-btn !px-2 !py-0.5 text-[10px]"
                      >
                        start
                      </button>
                      <button
                        phx-click="stop_container"
                        phx-value-id={mget(@machine, "id")}
                        phx-value-name={c["name"]}
                        class="ghost-btn !px-2 !py-0.5 text-[10px]"
                      >
                        stop
                      </button>
                      <button
                        phx-click="delete_container"
                        phx-value-id={mget(@machine, "id")}
                        phx-value-name={c["name"]}
                        class="ghost-btn !text-red !px-2 !py-0.5 text-[10px]"
                      >
                        delete
                      </button>
                    </div>
                  </div>
                  <%= if c["ipv4"] != "" and c["ipv4"] != nil do %>
                    <div class="mt-1.5 flex items-center gap-1.5 border-t border-border/50 pt-1.5">
                      <span class="text-gray-500">ssh</span>
                      <code class="font-mono text-[10px] text-green-400 truncate">root@<%= c["ipv4"] %></code>
                      <button
                        type="button"
                        id={"copy_ssh_#{c["name"]}"}
                        phx-hook="CopyToClipboard"
                        data-copy-text={"ssh root@#{c["ipv4"]}"}
                        class="ml-auto text-[10px] bg-surface-2 hover:bg-surface border border-border rounded px-1.5 py-0.5 text-text-secondary"
                      >
                        copy
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
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

  #
  # Sidebar header componen
  # Contains information around the sidebar context, will take params but this will be specific to sidebar
  #
  defp status_dot("ready"), do: "bg-green"
  defp status_dot("enrolled"), do: "bg-yellow"
  defp status_dot("probing"), do: "bg-yellow"
  defp status_dot("unreachable"), do: "bg-red"
  defp status_dot(_), do: "bg-gray-500"

  defp container_dot("Running"), do: "bg-green"
  defp container_dot("Stopped"), do: "bg-red"
  defp container_dot(_), do: "bg-gray-500"

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

  # Safely read a key from a machine map (string keys) or struct (atom keys).
  defp mget(machine, key) when is_binary(key) do
    case Map.get(machine, key) do
      nil -> Map.get(machine, String.to_atom(key))
      val -> val
    end
  end
end

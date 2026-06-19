defmodule TunneldWeb.Live.Components.Sidebar.Details do
  @moduledoc """
  The list of sidebar details to render.

  Renders one of several views selected by the parent LiveView:

  - `:system_overview` - default "all good" panel
  - `:resource`        - a single resource's details and actions
  - `:ethernet`        - upstream/downstream interface link state
  - `:dns_server`      - upstream DNS server configuration
  - `:authentication`  - login reset
  - `:service`         - system service logs and restart
  - `:mesh`            - mesh relay configuration form
  - `:mesh_node`       - a single mesh peer's details
  """

  use TunneldWeb, :live_component
  import TunneldWeb.Live.Components.HelpIcon

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    view = Map.get(assigns, :view, socket.assigns[:view] || :system_overview)
    data = Map.get(assigns, :data, %{})
    selection = Map.get(assigns, :selection, socket.assigns[:selection] || nil)
    obfuscated = Map.get(assigns, :obfuscated, false)

    socket =
      socket
      |> assign_new(:obfuscated, fn -> false end)
      |> assign(:view, view)
      |> assign(:data, data)
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
          class="flex items-center justify-center gap-1 bg-surface p-2 cursor-pointer rounded-md"
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
          class="flex items-center justify-center gap-1 bg-red p-2 cursor-pointer rounded-md"
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
              <span class={"ml-1 w-[13px] h-[13px] rounded-full inline-block align-middle #{pool_health_dot(health[:status])}"}></span>
              <span class="ml-1 capitalize"><%= human_health(health[:status]) %></span>
              <%= if is_number(health[:up]) and is_number(health[:total]) do %>
                <span class="ml-1 text-xs text-gray-300">(<%= health[:up] %>/<%= health[:total] %> up)</span>
              <% end %>
            </div>
            <div :if={@data[:lan_url]} class="text-sm truncate">
              <span class="font-bold">LAN URL:</span>
              <span class="ml-1 font-mono text-xs"><%= @data[:lan_url] %></span>
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
                      <span class={"w-2 h-2 rounded-full inline-block #{if up?, do: "bg-green", else: "bg-yellow"}"}></span>
                      <span class="font-mono text-xs text-gray-300"><%= mask(@obfuscated, entry) %></span>
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
        body: "All DNS queries on the subnet are forwarded to this server. Use a public resolver like 1.1.1.1 or a local Pi-hole on your network."
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
          <.icon class="w-4 h-4" name="hero-pencil-square" />
          Change DNS Server
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

        :nginx ->
          %{
            id: service,
            name: service |> Atom.to_string() |> String.capitalize(),
            description:
              "Reverse proxy/load balancer that fronts your exposed resources and distributes traffic."
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
          phx-value-data={Jason.encode!(%{ "id" => Map.get(@service, :id)})}
          phx-click-loading="opacity-50 cursor-wait"
          class="flex items-center justify-center gap-1 bg-surface p-2 cursor-pointer rounded-md"
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


  @spec render(%{:view => :mesh, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  def render(%{view: :mesh} = assigns) do
    mesh_state =
      try do
        if _pid = GenServer.whereis(Tunneld.Servers.Mesh) do
          Tunneld.Servers.Mesh.get_state()
        else
          %{status: :disabled, peers: %{}}
        end
      catch
        :exit, _ -> %{status: :connecting, peers: %{}}
      end

    config = Application.get_env(:tunneld, :mesh, [])
    coordinator_url = Keyword.get(config, :coordinator_url, "")
    token = Keyword.get(config, :token, "")
    node_name = Keyword.get(config, :node_name, "")
    wg_mtu = mesh_state[:wg_mtu] || 1280
    peers = mesh_state[:peers] || {}

    assigns =
      assigns
      |> assign(:mesh_state, mesh_state)
      |> assign(:status, mesh_state[:status] || :disabled)
      |> assign(:relay_endpoint, mesh_state[:relay_endpoint])
      |> assign(:relay_pubkey, mesh_state[:relay_pubkey])
      |> assign(:mesh_ip, mesh_state[:mesh_ip])
      |> assign(:last_sync, mesh_state[:last_sync])
      |> assign(:peer_count, map_size(peers))
      |> assign(:coordinator_url, coordinator_url)
      |> assign(:token, token)
      |> assign(:node_name, node_name)
      |> assign(:wg_mtu, wg_mtu)

    ~H"""
    <div class="p-4 space-y-6 min-h-full">
      <%= sidebar_header(assigns, %{
        header: "Mesh Configuration",
        body: "Connect this node to a tunneld-relay for mesh networking between instances."
      }) %>

      <div class="space-y-3">
        <div class="bg-surface rounded-lg p-3 space-y-2 text-xs text-gray-300">
          <div class="flex items-center justify-between">
            <span class="text-gray-400 font-semibold">Status</span>
            <span class="capitalize"><%= @status %></span>
          </div>
          <div :if={@mesh_ip} class="flex items-center justify-between">
            <span class="text-gray-400 font-semibold">Mesh IP</span>
            <span class="font-mono text-[10px]"><%= @mesh_ip %></span>
          </div>
          <div :if={@peer_count > 0} class="flex items-center justify-between">
            <span class="text-gray-400 font-semibold">Peers</span>
            <span class="font-mono text-[10px]"><%= @peer_count %></span>
          </div>
          <div :if={@last_sync} class="flex items-center justify-between">
            <span class="text-gray-400 font-semibold">Last Sync</span>
            <span class="font-mono text-[10px]"><%= Calendar.strftime(@last_sync, "%H:%M:%S") %></span>
          </div>
          <div :if={@relay_endpoint} class="flex items-center justify-between">
            <span class="text-gray-400 font-semibold">Relay Endpoint</span>
            <span class="font-mono text-[10px] break-all max-w-[200px]"><%= @relay_endpoint %></span>
          </div>
          <div :if={@relay_pubkey} class="flex items-center justify-between">
            <span class="text-gray-400 font-semibold">Relay Pubkey</span>
            <div class="flex items-center gap-1.5">
              <span class="font-mono text-[10px]"><%= String.slice(@relay_pubkey, 0, 20) <> "..." %></span>
            </div>
          </div>
        </div>
      </div>

      <div class="text-sm text-text-secondary">
        Set these values to connect to the relay.
        A tunneld-relay instance is required. See documentation for deployment.
      </div>

      <form phx-submit="save_mesh_config" class="space-y-3">
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Relay URL</label>
          <input
            type="url"
            name="coordinator_url"
            value={@coordinator_url}
            placeholder="http://relay.example.com:4000"
            class="tunl-input"
          />
        </div>
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Token</label>
          <input
            type="password"
            name="token"
            value={@token}
            placeholder="shared-secret"
            class="tunl-input"
          />
        </div>
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Node Name</label>
          <input
            type="text"
            name="node_name"
            value={@node_name}
            placeholder="living-room-gateway"
            class="tunl-input"
          />
        </div>
        <div>
          <label class="text-xs text-text-secondary mb-1 block">WireGuard MTU<.help_icon text="Maximum transmission unit for the WireGuard mesh interface. Default 1280 is safe for all network types including mobile data and CGNAT. Increase to 1420 for Ethernet/Wi-Fi links where the 1500 byte link MTU minus 80 bytes of WireGuard overhead fits cleanly. Setting too high causes packet loss and jitter." /></label>
          <input
            type="number"
            name="wg_mtu"
            value={@wg_mtu}
            min="1280"
            max="1500"
            placeholder="1280"
            class="tunl-input"
          />
        </div>
        <button
          type="submit"
          class="w-full p-3 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 bg-accent hover:bg-accent-light"
        >
          <.icon class="w-4 h-4" name="hero-check" />
          Save Mesh Config
        </button>
      </form>
    </div>
    """
  end

  @spec render(%{:view => :mesh_node, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :mesh_node} = assigns) do
    peer_id = Map.get(assigns.selection || %{}, :id, "")
    mesh_state =
      try do
        if _pid = GenServer.whereis(Tunneld.Servers.Mesh) do
          Tunneld.Servers.Mesh.get_state()
        else
          %{status: :disabled, peers: %{}}
        end
      catch
        :exit, _ -> %{status: :connecting, peers: %{}}
      end

    peer = mesh_state[:peers] |> Map.values() |> Enum.find(fn p ->
      Map.get(p, "node_id", Map.get(p, :node_id, "")) == peer_id
    end)

    name = if peer, do: Map.get(peer, "name", Map.get(peer, :name, "—")), else: "—"
    ip = if peer, do: Map.get(peer, "mesh_ip", Map.get(peer, :mesh_ip, "—")), else: "—"
    shared_devices = if peer, do: Map.get(peer, "devices", Map.get(peer, :devices, [])), else: []
    peer_node_id = if peer, do: Map.get(peer, "node_id", Map.get(peer, :node_id, "")), else: ""
    country = if peer, do: Map.get(peer, "country_name", Map.get(peer, :country_name, "")), else: ""

    assigns =
      assigns
      |> assign(:peer_name, name)
      |> assign(:peer_ip, ip)
      |> assign(:peer_country, country)
      |> assign(:peer_node_id, peer_node_id)
      |> assign(:shared_devices, shared_devices)

    ~H"""
    <div class="p-4 space-y-6 min-h-full">
      <%= sidebar_header(assigns, %{
        header: @peer_name,
        body: "Mesh peer #{@peer_ip} · #{@peer_country}"
      }) %>

      <div :if={@peer_ip != "—"} class="space-y-3">
        <h3 class="text-[11px] tracking-[0.08em] uppercase text-text-secondary font-medium">Mesh IP</h3>
        <div class="bg-surface rounded-lg p-3 border border-border flex items-center justify-between">
          <span class="font-mono text-xs text-text-primary"><%= @peer_ip %>/32</span>
        </div>
      </div>

      <div :if={@shared_devices != []} class="space-y-3">
        <h3 class="text-[11px] tracking-[0.08em] uppercase text-text-secondary font-medium">Shared Devices</h3>
        <div :for={device <- @shared_devices} class="bg-surface rounded-lg p-3 border border-border flex items-center justify-between gap-2">
          <div class="flex flex-col min-w-0">
            <span class="font-mono text-xs text-text-primary"><%= device["mapped_ip"] %></span>
            <span class="font-mono text-[10px] text-text-tertiary">via <%= device["real_ip"] %></span>
          </div>
        </div>
      </div>

      <div :if={@peer_ip == "—" and @shared_devices == []} class="text-sm text-text-secondary italic">
        No shared devices
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
end
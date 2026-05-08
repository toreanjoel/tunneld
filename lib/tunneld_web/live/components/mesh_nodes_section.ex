defmodule TunneldWeb.Live.Components.MeshNodesSection do
  @moduledoc """
  Mesh peer nodes rendered as a responsive card grid with expandable devices and
  sync/disconnect action buttons.
  """
  use Phoenix.Component
  import TunneldWeb.Icons
  import TunneldWeb.Live.Components.SectionHeader

  attr :nodes, :list, default: []
  attr :highlight_id, :string, default: nil

  def mesh_nodes_section(assigns) do
    ~H"""
    <section class="mt-16">
      <.section_header>
        Mesh nodes
        <:actions>
          <button class="ghost-btn" phx-click="trigger_action" phx-value-action="mesh_sync" phx-value-data="{}">
            <.refresh size={16} /> Sync now
          </button>
          <button class="ghost-btn !text-red" phx-click="trigger_action" phx-value-action="disconnect_mesh" phx-value-data="{}">
            <.x size={16} /> Disconnect
          </button>
        </:actions>
      </.section_header>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <%= for node <- @nodes do %>
          <.mesh_node_card node={node} highlight={@highlight_id == node["id"]} />
        <% end %>
      </div>
    </section>
    """
  end

  attr :node, :map, required: true
  attr :highlight, :boolean, default: false

  defp mesh_node_card(assigns) do
    node = assigns.node
    node_id = Map.get(node, "id", "") |> to_string()
    safe_id = if node_id == "", do: nil, else: node_id
    is_self = Map.get(node, "self", false)
    devices = Map.get(node, :devices, Map.get(node, "devices", []))
    has_devices = is_list(devices) and length(devices) > 0
    mesh_ip = Map.get(node, "mesh_ip", "—")
    online = Map.get(node, "online", true)
    last_seen_raw = Map.get(node, "last_seen", "—")
    last_seen = format_last_seen(last_seen_raw, online)
    name = Map.get(node, "name", "—")
    region = Map.get(node, "region", nil)

    assigns = assign(assigns, node_id: node_id, is_self: is_self, devices: devices, has_devices: has_devices,
      mesh_ip: mesh_ip, online: online, last_seen: last_seen, name: name, region: region, safe_id: safe_id)

    ~H"""
    <div
      id={if @safe_id, do: "mesh-node-#{@safe_id}"}
      class={[
        "bg-surface border border-border rounded-xl p-4 flex flex-col justify-between gap-2.5 min-h-[140px] transition-colors duration-[120ms] group hover:bg-[#17161F] hover:border-[#2A2838]"
      ]}
      phx-click={if @has_devices and @safe_id, do: JS.toggle_class("hidden", to: "#mesh-node-#{@safe_id}-devices")}
    >
      <div class="flex justify-between items-start">
        <span class="text-sm text-text-primary font-medium"><%= @name %></span>
        <span class={"status-dot mt-1 #{if @online, do: "status-dot--green", else: "status-dot--gray"}"} />
      </div>

      <div class="flex gap-1 flex-wrap">
        <span :if={@is_self} class="bg-accent/10 text-accent px-2 py-0.5 rounded text-[11px] font-mono">
          this node
        </span>
        <span :if={@region} class="bg-surface-2 text-text-secondary px-2 py-0.5 rounded text-[11px] font-mono">
          <%= @region %>
        </span>
      </div>

      <div>
        <div class="font-mono text-sm text-text-primary"><%= @mesh_ip %></div>
        <div class="font-mono text-xs text-text-tertiary mt-0.5">
          <%= if @online, do: "seen #{@last_seen}", else: "offline" %>
        </div>
        <div :if={@has_devices} class="text-xs text-text-secondary mt-1.5 flex justify-between items-center">
          <span><%= length(@devices) %> shared devices</span>
          <span class="text-text-tertiary text-[11px] inline-flex">
            <.chevron_right size={14} />
          </span>
        </div>
      </div>

      <div
        :if={@has_devices}
        id={"mesh-node-#{@safe_id}-devices"}
        class="hidden mt-1 pt-2.5 border-t border-border flex flex-col gap-2"
      >
        <%= for d <- @devices do %>
          <% dtags = d[:tags] || d["tags"] || [] %>
          <div>
            <div class="flex justify-between">
              <span class="text-xs text-text-primary"><%= d[:name] || d["name"] %></span>
              <span class="font-mono text-[11px] text-text-secondary"><%= d[:ip] || d["ip"] %></span>
            </div>
            <div :if={dtags != []} class="flex gap-1 flex-wrap mt-0.5">
              <%= for t <- dtags do %>
                <span class="bg-surface-2 text-text-secondary border border-border px-1.5 py-0.5 rounded text-[10px] font-mono"><%= t %></span>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_last_seen(ts, false), do: ts
  defp format_last_seen("now", true), do: "now"
  defp format_last_seen("—", _), do: "—"
  defp format_last_seen(ts, true) when is_integer(ts) do
    now = System.os_time(:millisecond)
    diff_sec = div(now - ts, 1000)
    cond do
      diff_sec < 60 -> "now"
      diff_sec < 3600 -> "#{div(diff_sec, 60)}m ago"
      diff_sec < 86400 -> "#{div(diff_sec, 3600)}h ago"
      true -> "#{div(diff_sec, 86400)}d ago"
    end
  end
  defp format_last_seen(ts, true) when is_binary(ts), do: ts
end

defmodule TunneldWeb.Live.Components.MeshCard do
  @moduledoc """
  Mesh network hero card with 2D world map visualization, device pin,
  connection status, peer count, mesh IP, last sync time, and configure button.

  The map is entirely offline — country paths are compiled directly into
  Tunneld.GeoData.WorldMap from Natural Earth 110m TopoJSON.

  Peer pins are grouped by country code; multiple peers in the same country
  render as a single larger pin with a count badge.
  """
  use Phoenix.Component
  import TunneldWeb.Icons
  import TunneldWeb.Live.Components.MapPin

  attr :connected, :boolean, default: false
  attr :peer_count, :integer, default: 0
  attr :mesh_ip, :string, default: nil
  attr :last_sync, :string, default: nil
  attr :relay, :string, default: nil
  attr :geo_location, :map, default: nil
  attr :map_status, :atom, default: :loading
  attr :mesh_peers, :list, default: []

  def mesh_card(assigns) do
    grouped_peers = group_peers_by_country(assigns.mesh_peers)
    assigns = assign(assigns, :grouped_peers, grouped_peers)

    ~H"""
    <div class="hero-card flex flex-col">
      <div class="px-7 pt-6 pb-4 flex justify-between items-start relative z-[2]">
        <div class="text-[11px] tracking-[0.08em] uppercase text-accent font-medium">
          MESH NETWORK
        </div>
        <div :if={@connected} class="font-mono text-[11px] text-text-primary/75 leading-[1.7] text-right">
          <div><span class="text-text-tertiary">peers </span><%= @peer_count %></div>
          <div><span class="text-text-tertiary">mesh ip </span><%= @mesh_ip %></div>
          <div><span class="text-text-tertiary">sync </span><%= @last_sync %></div>
        </div>
      </div>

      <div class="relative flex-1 min-h-[200px]">
        <svg
          :if={@map_status in [:ready, :stale, :geo_failed]}
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 800 450"
          class="absolute inset-0 w-full h-full"
          preserveAspectRatio="xMidYMid meet"
        >
          <Tunneld.GeoData.WorldMap.world_map />
          <.map_pin
            :if={@geo_location}
            node={%{
              id: "local",
              name: "This device",
              ip: Map.get(@geo_location, :ip, "—"),
              country_code: Map.get(@geo_location, :country_code, ""),
              country_name: Map.get(@geo_location, :country_name, ""),
              is_local: true,
              latitude: Map.get(@geo_location, :latitude),
              longitude: Map.get(@geo_location, :longitude)
            }}
          />
          <.map_pin
            :for={entry <- @grouped_peers}
            :if={@geo_location}
            node={entry.node}
            count={entry.count}
          />
        </svg>

        <div :if={@map_status == :loading} class="absolute inset-0 flex items-center justify-center">
          <span class="text-[13px] text-text-secondary italic">Locating device…</span>
        </div>

        <div :if={@map_status == :unavailable} class="absolute inset-0 flex items-center justify-center">
          <span class="text-[13px] text-text-secondary italic text-center px-4">
            Connect to a relay to see peer locations
          </span>
        </div>

        <div :if={@map_status == :geo_failed} class="absolute inset-0 flex items-center justify-center">
          <span class="text-[13px] text-text-secondary italic z-10">
            Couldn't determine location
          </span>
        </div>

        <div
          :if={@map_status == :stale}
          class="absolute bottom-2 right-3 text-[10px] text-text-tertiary font-mono bg-[#0B0A14]/80 px-2 py-0.5 rounded z-[3]"
        >
          stale · auto-refresh hourly
        </div>
      </div>

      <div class="h-px bg-border mx-6" />

      <div class="px-7 py-5 flex items-center justify-between gap-4 bg-surface">
        <div class="flex-1 min-w-0">
          <div class="text-[11px] tracking-[0.08em] uppercase text-text-secondary font-medium mb-2">
            MESH
          </div>
          <div class="text-2xl text-text-primary font-medium -tracking-[0.01em] leading-tight">
            <%= if @connected, do: "#{@peer_count} peers", else: "Disabled" %>
          </div>
          <div class={"text-[13px] text-text-secondary mt-1.5 overflow-hidden text-ellipsis whitespace-nowrap #{if @connected, do: "font-mono", else: ""}"}>
            <%= if @connected, do: @relay, else: "No relay configured" %>
          </div>
        </div>
        <div class="flex gap-1">
          <button :if={@connected} class="ghost-btn !text-red" phx-click="trigger_action" phx-value-action="disconnect_mesh" phx-value-data="{}">
            Disconnect
          </button>
          <button :if={@connected} class="ghost-icon" phx-click="show_details" phx-value-type="mesh" phx-value-id="_" aria-label="Configure mesh">
            <.settings size={16} />
          </button>
          <button :if={!@connected} class="ghost-btn" phx-click="show_details" phx-value-type="mesh" phx-value-id="_">Configure</button>
        </div>
      </div>
    </div>
    """
  end

  defp group_peers_by_country(peers) do
    peers
    |> Enum.group_by(fn p ->
      cc = Map.get(p, "country_code", Map.get(p, :country_code, "")) |> String.upcase()
      if cc == "", do: "UNKNOWN", else: cc
    end)
    |> Enum.map(fn {cc, group} ->
      names = Enum.map(group, fn p -> Map.get(p, "name", Map.get(p, :name, "—")) end)
      ips = Enum.map(group, fn p -> Map.get(p, "public_ip", Map.get(p, :public_ip, "—")) end)
      first_with_geo = Enum.find(group, fn p ->
        lat = Map.get(p, "latitude") || Map.get(p, :latitude)
        lng = Map.get(p, "longitude") || Map.get(p, :longitude)
        is_number(lat) and is_number(lng)
      end)

      node = %{
        id: "peer-#{cc}",
        name: hd(names),
        ip: hd(ips),
        country_code: cc,
        country_name: Tunneld.GeoData.Centroids.name(cc) || cc,
        is_local: false,
        peer_names: names |> Enum.join(", "),
        latitude: if(first_with_geo, do: Map.get(first_with_geo, "latitude") || Map.get(first_with_geo, :latitude)),
        longitude: if(first_with_geo, do: Map.get(first_with_geo, "longitude") || Map.get(first_with_geo, :longitude))
      }

      %{node: node, count: length(group)}
    end)
  end
end

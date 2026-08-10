defmodule TunneldWeb.Live.Components.MapCard do
  @moduledoc """
  Renders managed-node geolocation on an inline SVG world map.

  Shows pins for the gateway and any managed machines/VMs whose location is
  known, plus an honest offline/unavailable state when location has not been
  resolved (for example in local mock mode without a remote geo provider).
  """

  use TunneldWeb, :live_component

  alias Tunneld.GeoData.WorldMap

  attr :geo_location, :map, default: nil
  attr :map_status, :atom, default: :loading
  attr :nodes, :list, default: []

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-[#0D0C16] border border-border rounded-xl h-full flex flex-col overflow-hidden">
      <svg viewBox="0 0 800 450" class="w-full h-full" preserveAspectRatio="xMidYMid meet">
        <defs>
          <clipPath id="world-clip">
            <rect x="0" y="0" width="800" height="450" />
          </clipPath>
        </defs>
        <g
          fill="#1C1B26"
          stroke="#1C1B26"
          stroke-width="0.5"
          stroke-linejoin="round"
          clip-path="url(#world-clip)"
        >
          <%= for d <- WorldMap.paths() do %>
            <path d={d} />
          <% end %>
        </g>
        <%= if @map_status == :ready and @geo_location do %>
          <.pin geo={@geo_location} label="gateway" color="#06b6d4" ip="" country="Gateway location" />
        <% end %>
        <%= for node <- @nodes do %>
          <.pin
            geo={node}
            label={Map.get(node, :label, "node")}
            color="#a78bfa"
            ip={Map.get(node, :ip, "")}
            country={Map.get(node, :country, "")}
          />
        <% end %>
      </svg>
    </div>
    """
  end

  attr :geo, :map, required: true
  attr :label, :string, default: "node"
  attr :color, :string, default: "#06b6d4"
  attr :ip, :string, default: ""
  attr :country, :string, default: ""

  def pin(assigns) do
    {x, y} = project(assigns.geo.longitude, assigns.geo.latitude)
    assigns = assign(assigns, :x, x) |> assign(:y, y)

    ~H"""
    <g
      transform={"translate(#{@x} #{@y})"}
      phx-hook="MapPinHover"
      id={"pin-#{@label}"}
      data-pin-name={@label}
      data-pin-country={@country}
      data-pin-ip={@ip}
    >
      <circle r="6" fill="none" stroke={@color} stroke-width="2" opacity="0.6">
        <animate attributeName="r" values="4;12" dur="1.5s" repeatCount="indefinite" />
        <animate attributeName="opacity" values="0.6;0" dur="1.5s" repeatCount="indefinite" />
      </circle>
      <circle r="3" fill={@color} />
      <title><%= @label %></title>
    </g>
    """
  end

  defp project(lon, lat) do
    x = (lon + 180) * 800 / 360
    y = (90 - lat) * 450 / 180
    {Float.round(x, 1), Float.round(y, 1)}
  end
end

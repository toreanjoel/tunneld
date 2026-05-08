defmodule TunneldWeb.Live.Components.MapPin do
  @moduledoc """
  Renders a pin circle on the world map SVG for a tunnel node.

  Position is derived from the node's country_code via Tunneld.GeoData.Centroids,
  with seeded jitter applied server-side for privacy.
  """

  use Phoenix.Component

  attr :node, :map, required: true, doc: "%{id, name, ip, country_code, is_local}"
  attr :count, :integer, default: 1

  @doc """
  Renders a map pin for a single node. The `count` attr is forward-compatible
  for clustering when peer pins are added.

  ## Node map keys
    - `:id` — unique identifier
    - `:name` — display name
    - `:ip` — public IP (used to seed jitter)
    - `:country_code` — ISO 3166-1 alpha-2
    - `:country_name` — full country name
    - `:is_local` — true if this is the local device
  """
  def map_pin(assigns) do
    node = assigns.node
    country_code = Map.get(node, :country_code)
    ip = Map.get(node, :ip, "")
    is_local = Map.get(node, :is_local, false)
    country_name = Map.get(node, :country_name, "")
    name = Map.get(node, :name, "Unknown")

    {cx, cy} =
      case Tunneld.GeoData.Centroids.get(country_code) do
        {x, y} when is_integer(x) and is_integer(y) ->
          # Apply seeded jitter so the pin isn't exactly on the centroid
          jx = seeded_jitter(ip <> "_x", 6)
          jy = seeded_jitter(ip <> "_y", 6)
          {x + jx, y + jy}

        _ ->
          # Fallback to center of canvas if country unknown
          {400, 225}
      end

    pulse_class = if is_local, do: "animate-pulse-pin", else: ""
    tooltip_id = "pin-tooltip-#{Map.get(node, :id, "unknown")}"

    assigns =
      assigns
      |> assign(:cx, cx)
      |> assign(:cy, cy)
      |> assign(:pulse_class, pulse_class)
      |> assign(:is_local, is_local)
      |> assign(:country_name, country_name)
      |> assign(:name, name)
      |> assign(:ip, ip)
      |> assign(:tooltip_id, tooltip_id)

    ~H"""
    <g
      id={"map-pin-#{@tooltip_id}"}
      class="map-pin-group cursor-default"
      data-pin-name={@name}
      data-pin-country={@country_name}
      data-pin-ip={@ip}
      data-pin-is-local={to_string(@is_local)}
      phx-hook="MapPinHover"
    >
      <circle
        :if={@is_local}
        cx={@cx}
        cy={@cy}
        r="12"
        fill="#2ECC71"
        opacity="0.20"
        class={["pointer-events-none", @pulse_class]}
      />
      <circle
        cx={@cx}
        cy={@cy}
        r="6"
        fill="#2ECC71"
        class="pointer-events-auto"
      />
    </g>
    """
  end

  defp seeded_jitter(seed, range) do
    val = :erlang.phash2(seed, 2 * range + 1)
    val - range
  end
end

defmodule TunneldWeb.Live.Components.MapPin do
  @moduledoc """
  Renders a pin circle on the world map SVG for one or more tunnel nodes.

  Position is derived from the country_code via Tunneld.GeoData.Centroids,
  with seeded jitter applied server-side for privacy.

  When `count > 1`, the pin renders larger and shows a count badge,
  and the tooltip lists all peer names.
  """

  use Phoenix.Component

  attr :node, :map, required: true, doc: "%{id, name, ip, country_code, is_local, peer_names}"
  attr :count, :integer, default: 1

  def map_pin(assigns) do
    node = assigns.node
    country_code = Map.get(node, :country_code)
    ip = Map.get(node, :ip, "")
    is_local = Map.get(node, :is_local, false)
    country_name = Map.get(node, :country_name, "")
    name = Map.get(node, :name, "Unknown")
    count = assigns.count
    peer_names = Map.get(node, :peer_names, name)
    latitude = Map.get(node, :latitude) || Map.get(node, "latitude")
    longitude = Map.get(node, :longitude) || Map.get(node, "longitude")

    {cx, cy} =
      case project_or_fallback(latitude, longitude, country_code, ip) do
        {x, y} when is_number(x) and is_number(y) ->
          jx = seeded_jitter(ip <> "_x", 6)
          jy = seeded_jitter(ip <> "_y", 6)
          {x + jx, y + jy}

        _ ->
          {400, 225}
      end

    mult = count > 1
    r = if mult, do: 8, else: 6
    halo_r = if mult, do: 16, else: 12
    tooltip_id = "pin-tooltip-#{Map.get(node, :id, "unknown")}"

    assigns =
      assigns
      |> assign(:cx, cx)
      |> assign(:cy, cy)
      |> assign(:r, r)
      |> assign(:halo_r, halo_r)
      |> assign(:mult, mult)
      |> assign(:is_local, is_local)
      |> assign(:country_name, country_name)
      |> assign(:name, name)
      |> assign(:ip, ip)
      |> assign(:tooltip_id, tooltip_id)
      |> assign(:peer_names, peer_names)

    ~H"""
    <g
      id={"map-pin-#{@tooltip_id}"}
      class="map-pin-group cursor-default"
      data-pin-name={@peer_names}
      data-pin-country={@country_name}
      data-pin-ip={@ip}
      data-pin-count={to_string(@count)}
      data-pin-is-local={to_string(@is_local)}
      phx-hook="MapPinHover"
    >
      <circle
        :if={@is_local or @mult}
        cx={@cx}
        cy={@cy}
        r={@halo_r}
        fill="#2ECC71"
        opacity="0.20"
        class={["pointer-events-none", @is_local && "opacity-40"]}
      />
      <circle
        cx={@cx}
        cy={@cy}
        r={@r}
        fill="#2ECC71"
        class="pointer-events-auto"
      />
      <text
        :if={@mult}
        x={@cx}
        y={@cy}
        text-anchor="middle"
        dominant-baseline="central"
        fill="#0B0A14"
        font-size="9"
        font-family="Inter, sans-serif"
        font-weight="600"
        class="pointer-events-none"
      ><%= @count %></text>
    </g>
    """
  end

  defp project_or_fallback(lat, lng, _country_code, _ip)
       when is_number(lat) and is_number(lng) do
    cx = (lng + 180) / 360 * 800
    cy = (90 - lat) / 180 * 450
    {round(cx), round(cy)}
  end

  defp project_or_fallback(_lat, _lng, country_code, ip) do
    case Tunneld.GeoData.Centroids.get(country_code) do
      {x, y} when is_integer(x) and is_integer(y) ->
        jx = seeded_jitter(ip <> "_x", 6)
        jy = seeded_jitter(ip <> "_y", 6)
        {x + jx, y + jy}

      _ ->
        nil
    end
  end

  defp seeded_jitter(seed, range) do
    val = :erlang.phash2(seed, 2 * range + 1)
    val - range
  end
end

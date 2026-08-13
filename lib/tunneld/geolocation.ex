defmodule Tunneld.Geolocation do
  @moduledoc """
  Periodically fetches the device's public IP and geolocation, caches the
  result, and broadcasts updates via Phoenix.PubSub on topic "geolocation:device".

  State:
    - `location` - the last successful location result, or nil
    - `status` - `:ok`, `:stale`, or `:unavailable`
    - `last_updated` - monotonic time of last successful fetch
    - `error_count` - consecutive failure count for backoff
    - `refresh_timer` - reference for the scheduled refresh timer

  On start, the first fetch runs asynchronously (fire and forget via Task)
  so it doesn't block app boot.
  """

  use GenServer
  require Logger

  @topic "geolocation:device"
  @refresh_interval_ms :timer.hours(1)
  @ip_endpoints [
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
    "https://api.ipify.org"
  ]
  @geo_endpoints [
    {"https://ipapi.co/%s/json/",
     %{
       "country" => "country_name",
       "country_code" => "country_code",
       "latitude" => "latitude",
       "longitude" => "longitude"
     }},
    {"https://ipinfo.io/%s/json",
     %{
       "country" => "country",
       "country_code" => "country",
       "latitude" => "loc",
       "longitude" => "loc"
     }}
  ]
  @ip_timeout 3_000
  @cache :tunneld_geolocation_cache
  @cache_ttl_ms :timer.hours(24)
  @cache_error_ttl_ms :timer.minutes(5)

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Returns the current location status: `{:ok, location}`, `:stale`, or `:unavailable`."
  def get_location do
    GenServer.call(__MODULE__, :get_location)
  end

  @doc "Trigger an immediate geolocation refresh. Result broadcast via PubSub."
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Geolocate an IP address. Returns `{:ok, location}` or `:error`.

  Results are cached: the dashboard calls this once per managed machine on
  every mount and every machine change, and the free providers rate-limit
  hard. A 429 from the first provider is what pushed lookups onto the
  second one in the first place.
  """
  def geolocate(ip) when is_binary(ip) do
    if mock?() do
      {:ok,
       %{
         ip: ip,
         country_code: "US",
         country_name: "United States",
         latitude: 37.7749,
         longitude: -122.4194
       }}
    else
      case cache_get(ip) do
        {:ok, cached} ->
          cached

        :miss ->
          result =
            case fetch_geolocation(ip) do
              {:ok, geo} -> {:ok, Map.put(geo, :ip, ip)}
              _ -> :error
            end

          cache_put(ip, result)
          result
      end
    end
  end

  @impl true
  def init(_) do
    ensure_cache()

    if mock?() do
      location = %{
        ip: "192.168.1.1",
        country_code: "US",
        country_name: "United States",
        latitude: 37.7749,
        longitude: -122.4194
      }

      ref = Process.send_after(self(), :do_refresh, @refresh_interval_ms)

      state = %{
        location: location,
        status: :ok,
        last_updated: System.monotonic_time(),
        error_count: 0,
        refresh_timer: ref
      }

      broadcast({:location_updated, location})
      {:ok, state}
    else
      caller = self()
      Task.start(fn -> initial_fetch(caller) end)

      {:ok,
       %{
         location: nil,
         status: :unavailable,
         last_updated: nil,
         error_count: 0,
         refresh_timer: nil
       }}
    end
  end

  @impl true
  def handle_call(:get_location, _from, state) do
    case state.location do
      nil when state.status == :unavailable -> {:reply, :unavailable, state}
      nil -> {:reply, :unavailable, state}
      loc -> {:reply, {:ok, loc}, state}
    end
  end

  @impl true
  def handle_cast(:refresh, state) do
    cancel_timer(state.refresh_timer)
    fetch_and_update(state)
  end

  @impl true
  def handle_info(:do_refresh, state) do
    fetch_and_update(state)
  end

  @impl true
  def handle_info({:initial_fetch_done, result}, state) do
    case result do
      {:ok, location} ->
        state = %{
          state
          | location: location,
            status: :ok,
            last_updated: System.monotonic_time(),
            error_count: 0
        }

        broadcast({:location_updated, location})
        {:noreply, %{state | refresh_timer: schedule_refresh(state)}}

      {:error, :ip_ok_no_geo} ->
        broadcast(:geo_failed)

        {:noreply,
         %{state | error_count: state.error_count + 1, refresh_timer: retry_timer(state)}}

      {:error, :all_exhausted} ->
        broadcast(:location_unavailable)

        {:noreply,
         %{state | error_count: state.error_count + 1, refresh_timer: retry_timer(state)}}

      _ ->
        {:noreply,
         %{state | error_count: state.error_count + 1, refresh_timer: retry_timer(state)}}
    end
  end

  defp initial_fetch(caller) do
    result = fetch_location()
    send(caller, {:initial_fetch_done, result})
  end

  defp fetch_and_update(state) do
    ref = schedule_refresh(%{state | refresh_timer: nil})

    case fetch_location() do
      {:ok, location} ->
        new_state = %{
          state
          | location: location,
            status: :ok,
            last_updated: System.monotonic_time(),
            error_count: 0
        }

        broadcast({:location_updated, location})
        {:noreply, %{new_state | refresh_timer: ref}}

      {:error, :ip_ok_no_geo} ->
        new_state = %{state | error_count: state.error_count + 1}
        broadcast(:geo_failed)
        {:noreply, %{new_state | refresh_timer: ref}}

      {:error, :all_exhausted} ->
        new_state = %{state | error_count: state.error_count + 1}
        broadcast(:location_unavailable)
        {:noreply, %{new_state | refresh_timer: ref}}

      _ ->
        new_state = %{state | error_count: state.error_count + 1}
        broadcast(:location_unavailable)
        {:noreply, %{new_state | refresh_timer: ref}}
    end
  end

  defp fetch_location do
    with {:ok, ip} <- fetch_public_ip() do
      case fetch_geolocation(ip) do
        {:ok, geo} -> {:ok, Map.put(geo, :ip, ip)}
        :error -> {:error, :ip_ok_no_geo}
        _ -> {:error, :ip_ok_no_geo}
      end
    end
  end

  defp fetch_public_ip do
    try_endpoints(@ip_endpoints, fn url ->
      case HTTPoison.get(url, [], timeout: @ip_timeout, recv_timeout: @ip_timeout) do
        {:ok, %{status_code: 200, body: body}} ->
          ip = String.trim(body)
          if valid_ip?(ip), do: {:ok, ip}, else: :error

        _ ->
          :error
      end
    end)
  end

  defp fetch_geolocation(ip) do
    try_endpoints(@geo_endpoints, fn {url_template, field_map} ->
      url = String.replace(url_template, "%s", ip)

      case HTTPoison.get(url, [], timeout: @ip_timeout, recv_timeout: @ip_timeout) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} -> parse_geo_response(data, field_map)
            _ -> :error
          end

        _ ->
          :error
      end
    end)
  end

  @doc false
  # Public only so the provider response shapes can be tested without a network
  # round trip. Not part of the module's interface.
  def parse_geo_response(data, field_map) do
    country_code = get_field(data, field_map, "country_code")
    country_name = get_field(data, field_map, "country")
    lat = get_field(data, field_map, "latitude")
    lng = get_field(data, field_map, "longitude")

    # ipinfo.io answers with ONE field - "loc" => "-26.12,28.03" - so the field
    # map points both latitude and longitude at it. Running that through
    # parse_float/1 twice returns the latitude twice, because Float.parse stops
    # at the comma. Every ipinfo-sourced pin therefore plotted at
    # (lat, lat) - which for this gateway is the middle of the South Atlantic.
    # Split the pair when both fields resolve to the same combined string.
    {lat, lng} =
      cond do
        is_binary(lat) and lat == lng and String.contains?(lat, ",") ->
          parse_loc(lat)

        is_nil(lat) and is_nil(lng) ->
          case Map.get(data, "loc") do
            str when is_binary(str) -> parse_loc(str)
            _ -> {nil, nil}
          end

        true ->
          {parse_float(lat), parse_float(lng)}
      end

    if country_code && valid_coords?(lat, lng) do
      {:ok,
       %{
         country_code: String.upcase(country_code) |> String.trim(),
         country_name: country_name |> String.trim(),
         latitude: lat,
         longitude: lng
       }}
    else
      :error
    end
  end

  # A provider that answers 200 with a null island or an out-of-range pair is
  # worse than one that fails: the pin lands somewhere plausible-looking and
  # nobody questions it. Reject it and let try_endpoints/2 fall through.
  defp valid_coords?(lat, lng)
       when is_number(lat) and is_number(lng) and lat >= -90 and lat <= 90 and lng >= -180 and
              lng <= 180,
       do: true

  defp valid_coords?(_, _), do: false

  defp get_field(data, field_map, key) do
    field = Map.get(field_map, key)
    if field, do: Map.get(data, field), else: nil
  end

  defp parse_loc(str) do
    case String.split(str, ",", parts: 2) do
      [lat, lng] -> {parse_float(lat), parse_float(lng)}
      _ -> {nil, nil}
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(n) when is_number(n), do: n

  defp parse_float(str) when is_binary(str) do
    case Float.parse(String.trim(str)) do
      {val, _} -> val
      :error -> nil
    end
  end

  defp try_endpoints([], _fun), do: {:error, :all_exhausted}

  defp try_endpoints([ep | rest], fun) do
    case fun.(ep) do
      {:ok, result} -> {:ok, result}
      _ -> try_endpoints(rest, fun)
    end
  end

  defp valid_ip?(ip) do
    ip =~ ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
  end

  defp schedule_refresh(_state) do
    Process.send_after(self(), :do_refresh, @refresh_interval_ms)
  end

  defp retry_timer(state) do
    delay = min(300_000, (30_000 * :math.pow(2, min(state.error_count, 4))) |> round())
    Process.send_after(self(), :do_refresh, delay)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, @topic, message)
  end

  # --- per-IP lookup cache -------------------------------------------------
  # A plain public ETS table owned by this GenServer. Reads and writes happen in
  # the calling process (usually a LiveView), so a slow HTTP lookup never
  # serialises behind this server's mailbox.

  defp ensure_cache do
    if :ets.whereis(@cache) == :undefined do
      :ets.new(@cache, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  defp cache_get(ip) do
    case :ets.lookup(@cache, ip) do
      [{^ip, result, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at, do: {:ok, result}, else: :miss

      _ ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_put(ip, result) do
    ttl = if match?({:ok, _}, result), do: @cache_ttl_ms, else: @cache_error_ttl_ms
    :ets.insert(@cache, {ip, result, System.monotonic_time(:millisecond) + ttl})
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)
end

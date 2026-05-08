defmodule Tunneld.Geolocation do
  @moduledoc """
  Periodically fetches the device's public IP and geolocation, caches the
  result, and broadcasts updates via Phoenix.PubSub on topic "geolocation:device".

  State:
    - `location` — the last successful location result, or nil
    - `status` — `:ok`, `:stale`, or `:unavailable`
    - `last_updated` — monotonic time of last successful fetch
    - `error_count` — consecutive failure count for backoff
    - `refresh_timer` — reference for the scheduled refresh timer

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
    {"https://ipapi.co/%s/json/", %{"country" => "country_name", "country_code" => "country_code", "latitude" => "latitude", "longitude" => "longitude"}},
    {"https://ipinfo.io/%s/json", %{"country" => "country", "country_code" => "country", "latitude" => "loc", "longitude" => "loc"}}
  ]
  @ip_timeout 3_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Returns the current location status.

  ## Return values
    - `{:ok, location}` — location is available and fresh
    - `:stale` — location is cached but hasn't been refreshed recently
    - `:unavailable` — no location data was ever obtained
  """
  def get_location do
    GenServer.call(__MODULE__, :get_location)
  end

  @doc """
  Triggers an immediate refresh of the geolocation data.
  Returns immediately; the result will be broadcast via PubSub.
  """
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @impl true
  def init(_) do
    if mock?() do
      location = %{
        ip: "192.168.1.1",
        country_code: "US",
        country_name: "United States",
        latitude: 37.7749,
        longitude: -122.4194
      }
      ref = Process.send_after(self(), :do_refresh, @refresh_interval_ms)
      state = %{location: location, status: :ok, last_updated: System.monotonic_time(), error_count: 0, refresh_timer: ref}
      broadcast({:location_updated, location})
      {:ok, state}
    else
      caller = self()
      Task.start(fn -> initial_fetch(caller) end)
      {:ok, %{location: nil, status: :unavailable, last_updated: nil, error_count: 0, refresh_timer: nil}}
    end
  end

  @impl true
  def handle_call(:get_location, _from, state) do
    case state.location do
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
        state = %{state | location: location, status: :ok, last_updated: System.monotonic_time(), error_count: 0}
        broadcast({:location_updated, location})
        {:noreply, schedule_refresh(state)}

      {:error, :all_exhausted} ->
        broadcast(:location_unavailable)
        {:noreply, schedule_refresh(state)}

      _ ->
        {:noreply, schedule_refresh(state)}
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
        new_state = %{state | location: location, status: :ok, last_updated: System.monotonic_time(), error_count: 0}
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

  defp parse_geo_response(data, field_map) do
    country_code = get_field(data, field_map, "country_code")
    country_name = get_field(data, field_map, "country")
    lat = get_field(data, field_map, "latitude")
    lng = get_field(data, field_map, "longitude")

    # ipinfo.io returns "loc" as a comma-separated pair like "37.4,-122.0"
    {lat, lng} =
      if is_nil(lat) and is_nil(lng) do
        loc = Map.get(data, "loc") || Map.get(data, "latitude")
        case loc do
          str when is_binary(str) -> parse_loc(str)
          _ -> {nil, nil}
        end
      else
        {parse_float(lat), parse_float(lng)}
      end

    if country_code do
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

  defp schedule_refresh(state) do
    cancel_timer(state.refresh_timer)
    ref = Process.send_after(self(), :do_refresh, @refresh_interval_ms)
    ref
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, @topic, message)
  end

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)
end

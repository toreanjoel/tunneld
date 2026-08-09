defmodule TunneldWeb.DeviceController do
  @moduledoc """
  Device-facing (no-login) read API for subnet devices.

  These endpoints let a device on the gateway's subnet query machine,
  health, and exposure data without credentials. The caller is resolved from
  its DHCP lease (same model as Quick Expose), so only devices that have a
  lease from this gateway are allowed.

  Endpoints (under /api/v1/device):
    GET /api/v1/device/machines                 list machines + status + capabilities
    GET /api/v1/device/machines/:id             machine detail + health
    GET /api/v1/device/resources                list exposed resources
    GET /api/v1/device/health                   gateway + service status
  """

  use TunneldWeb, :controller

  @doc "List enrolled machines with status and capabilities."
  def machines(conn, _params) do
    with {:ok, _ip, _mac} <- resolve_device(conn) do
      machines =
        Tunneld.Machines.list()
        |> Enum.map(fn m ->
          %{
            id: m["id"],
            name: m["name"],
            address: m["address"],
            location: m["location"],
            kind: m["kind"],
            status: m["status"],
            last_seen: m["last_seen"],
            capabilities: m["capabilities"]
          }
        end)

      json(conn, %{machines: machines})
    else
      err -> render_error(err, conn)
    end
  end

  @doc "Machine detail plus reachability/health."
  def machine(conn, %{"id" => id}) do
    with {:ok, _ip, _mac} <- resolve_device(conn) do
      case Tunneld.Machines.get(id) do
        {:ok, machine} ->
          health = %{
            last_seen: machine["last_seen"],
            status: machine["status"],
            probed: not is_nil(machine["capabilities"])
          }

          json(conn, %{machine: machine, health: health})

        {:error, :not_found} ->
          conn |> put_status(404) |> json(%{error: "machine not found"})
      end
    else
      err -> render_error(err, conn)
    end
  end


  def resources(conn, _params) do
    with {:ok, _ip, _mac} <- resolve_device(conn) do
      resources =
        Tunneld.Servers.Resources.fetch_shares()
        |> Enum.map(fn r ->
          %{
            id: r.id,
            name: r.name,
            lan_url: r.lan_url,
            kind: r.kind,
            expose_source: r.expose_source,
            expose_machine_id: r.expose_machine_id,
            expose_container: r.expose_container,
            status: r.status,
            health: r.health
          }
        end)

      json(conn, %{resources: resources})
    else
      err -> render_error(err, conn)
    end
  end

  @doc "Gateway health + service status."
  def health(conn, _params) do
    with {:ok, _ip, _mac} <- resolve_device(conn) do
      services =
        Tunneld.Servers.Services.get_status()
        |> Enum.map(fn {name, up?} -> %{name: to_string(name), up: up?} end)

      json(conn, %{
        status: "ok",
        version: Application.spec(:tunneld, :vsn) |> to_string(),
        services: services
      })
    else
      err -> render_error(err, conn)
    end
  end

  # --- Device resolution (same model as Quick Expose) ---

  defp resolve_device(conn) do
    device_ip =
      :inet.ntoa(conn.remote_ip)
      |> to_string()

    devices = Tunneld.Servers.Devices.fetch_devices()

    case Enum.find(devices, &(&1.ip == device_ip)) do
      nil ->
        {:error, 403, %{error: "device not recognised on subnet - ensure it has a DHCP lease from this gateway"}}

      %{mac: mac} ->
        {:ok, device_ip, mac}
    end
  end

  defp render_error({:error, status, body}, conn) do
    conn
    |> put_status(status)
    |> json(body)
  end
end
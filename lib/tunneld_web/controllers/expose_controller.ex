defmodule TunneldWeb.ExposeController do
  @moduledoc """
  Quick Expose API - zero-credential endpoint for subnet devices to create,
  list, and remove local resources.

  The gateway resolves the caller from `conn.remote_ip`, validates it against
  an allowlist, and manages the full resource lifecycle. Each exposed service
  is reachable on the subnet at `http://<name>.tunneld.lan:18000` via dnsmasq.
  There is no public-internet exposure - relay/mesh exposure is future work.
  """

  use TunneldWeb, :controller
  require Logger

  # --- Actions ---

  def create(conn, params) do
    with {:ok, device_ip, mac} <- resolve_device(conn),
         :ok <- check_allowed(mac),
         {:ok, port, name} <- validate_body(params),
         :ok <- check_name_conflict(name) do
      create_and_enable_share(conn, device_ip, mac, port, name)
    else
      {:error, status, body} ->
        conn
        |> put_status(status)
        |> json(body)
    end
  end

  def delete(conn, %{"name" => name}) do
    with {:ok, _device_ip, mac} <- resolve_device(conn),
         :ok <- check_allowed(mac),
         {:ok, resource} <- find_expose_resource(name, mac) do
      Tunneld.Servers.Resources.remove_share(resource.id)
      json(conn, %{name: name, status: "removed"})
    else
      {:error, status, body} ->
        conn
        |> put_status(status)
        |> json(body)
    end
  end

  def index(conn, _params) do
    with {:ok, _device_ip, mac} <- resolve_device(conn),
         :ok <- check_allowed(mac) do
      shares =
        Tunneld.Servers.Resources.fetch_shares()
        |> Enum.filter(fn r ->
          r.expose_source == "device" and r.expose_device_mac == mac
        end)
        |> Enum.map(fn r ->
          %{
            name: r.name,
            lan_url: r.lan_url,
            port: extract_port(r)
          }
        end)

      json(conn, %{shares: shares})
    else
      {:error, status, body} ->
        conn
        |> put_status(status)
        |> json(body)
    end
  end

  # --- Helpers ---

  defp resolve_device(conn) do
    device_ip =
      :inet.ntoa(conn.remote_ip)
      |> to_string()

    devices = Tunneld.Servers.Devices.fetch_devices()

    case Enum.find(devices, &(&1.ip == device_ip)) do
      nil ->
        {:error, 403,
         %{
           error:
             "device not recognised on subnet - ensure it has a DHCP lease from this gateway"
         }}

      %{mac: mac} ->
        {:ok, device_ip, mac}
    end
  end

  defp check_allowed(mac) do
    if Tunneld.Servers.ExposeAllowed.allowed?(mac) do
      :ok
    else
      {:error, 403,
       %{
         error:
           "device not allowed - enable Quick Expose for this device from the gateway dashboard"
       }}
    end
  end

  defp validate_body(params) do
    port = params["port"]
    name = params["name"]

    cond do
      not is_integer(port) or port < 1 or port > 65535 ->
        {:error, 422, %{error: "port must be an integer between 1 and 65535"}}

      not is_binary(name) or String.trim(name) == "" ->
        {:error, 422, %{error: "name is required and must be a non-empty string"}}

      true ->
        stripped = strip_prefixes(name)

        if Regex.match?(~r/^[a-zA-Z0-9\-]{1,40}$/, stripped) do
          {:ok, port, stripped}
        else
          {:error, 422,
           %{
             error:
               "name must be alphanumeric and hyphens only, max 40 characters after stripping prefixes"
           }}
        end
    end
  end

  defp strip_prefixes(name) do
    name
    |> String.replace_prefix("pub:", "")
    |> String.replace_prefix("priv:", "")
    |> String.replace_prefix("public:", "")
    |> String.replace_prefix("private:", "")
  end

  defp check_name_conflict(name) do
    exists =
      Tunneld.Servers.Resources.fetch_shares()
      |> Enum.any?(&(&1.name == name))

    if exists do
      {:error, 409, %{error: "name already in use"}}
    else
      :ok
    end
  end

  defp create_and_enable_share(conn, device_ip, mac, port, name) do
    _result =
      Tunneld.Servers.Resources.add_share(%{
        "name" => name,
        "description" => "Quick Expose from #{device_ip}",
        "pool" => ["#{device_ip}:#{port}"],
        "expose_source" => "device",
        "expose_device_mac" => mac,
        "expose_device_ip" => device_ip
      })

    resource =
      Tunneld.Servers.Resources.fetch_shares()
      |> Enum.find(&(&1.name == name))

    if is_nil(resource) do
      conn
      |> put_status(500)
      |> json(%{error: "share was not created - please retry"})
    else
      lan_url = resource.lan_url || "http://#{Tunneld.Servers.Nginx.lan_hostname(name)}:#{Tunneld.Servers.Nginx.public_port()}"

      json(conn, %{
        name: name,
        lan_url: lan_url,
        device_ip: device_ip,
        port: port,
        note: "Resource is live - start your server on port #{port} to serve traffic"
      })
    end
  end

  defp find_expose_resource(name, mac) do
    resource =
      Tunneld.Servers.Resources.fetch_shares()
      |> Enum.find(fn r ->
        r.name == name and r.expose_source == "device"
      end)

    cond do
      is_nil(resource) ->
        {:error, 404, %{error: "share not found"}}

      resource.expose_device_mac != mac ->
        {:error, 403, %{error: "share not found"}}

      true ->
        {:ok, resource}
    end
  end

  defp extract_port(resource) do
    case resource.pool do
      [port_str | _] when is_binary(port_str) ->
        case String.split(port_str, ":", parts: 2) do
          [_, port] -> String.to_integer(port)
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
defmodule TunneldWeb.ExposeController do
  @moduledoc """
  Quick Expose API — zero-credential endpoint for subnet devices to create,
  list, and remove public Zrok shares.

  The gateway resolves the caller from `conn.remote_ip`, validates it against
  an allowlist, and manages the full share lifecycle.
  """

  use TunneldWeb, :controller
  require Logger

  # --- Actions ---

  def create(conn, params) do
    with {:ok, device_ip, mac} <- resolve_device(conn),
         :ok <- check_allowed(mac),
         {:ok, port, name} <- validate_body(params),
         :ok <- check_name_conflict(name),
         :ok <- check_zrok_config(),
         :ok <- check_zrok_enabled(),
         :ok <- check_connectivity() do
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
            public_url: public_url(r),
            port: extract_port(r),
            active: get_in(r.tunneld, ["enabled", "public"]) || false
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
             "device not recognised on subnet — ensure it has a DHCP lease from this gateway"
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
           "device not allowed — enable Quick Expose for this device from the gateway dashboard"
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

  defp check_zrok_config do
    case Tunneld.Servers.Zrok.get_api_endpoint() do
      nil ->
        {:error, 503,
         %{
           error:
             "no Zrok control plane configured — set it from the gateway dashboard"
         }}

      "<unset>" ->
        {:error, 503,
         %{
           error:
             "no Zrok control plane configured — set it from the gateway dashboard"
         }}

      _ ->
        :ok
    end
  end

  defp check_zrok_enabled do
    if Tunneld.Servers.Zrok.enabled?() do
      :ok
    else
      {:error, 503,
       %{
         error:
           "Zrok environment not enabled — enable it from the gateway dashboard"
       }}
    end
  end

  defp check_connectivity do
    if mock?() do
      :ok
    else
      case Tunneld.Servers.Zrok.get_api_endpoint() do
        nil ->
          :ok

        ep ->
          case URI.parse(ep).host do
            nil ->
              :ok

            host ->
              case :gen_tcp.connect(String.to_charlist(host), 443, [:binary, active: false], 3000) do
                {:ok, sock} ->
                  :gen_tcp.close(sock)
                  :ok

                _ ->
                  {:error, 503,
                   %{
                     error:
                       "gateway cannot reach the Zrok control plane — check internet connectivity"
                   }}
              end
          end
      end
    end
  end

  defp create_and_enable_share(conn, device_ip, mac, port, name) do
    _result =
      Tunneld.Servers.Resources.add_share(%{
        "name" => name,
        "description" => "Quick Expose from #{device_ip}",
        "pool" => ["#{device_ip}:#{port}"],
        "tunneld" => %{},
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
      |> json(%{error: "share was not created — please retry"})
    else
      pub_unit_id = get_in(resource.tunneld, ["units", "public", "id"])

      enabled? =
        if pub_unit_id do
          Tunneld.Servers.Resources.toggle_share(pub_unit_id, true)
          true
        else
          false
        end

      public_url = public_url(resource)
      lan_url = "http://#{name}.tunneld.lan"

      note =
        if enabled? do
          "Share is live — start your server on port #{port} to serve traffic"
        else
          "Share was created but not yet active — check the gateway dashboard"
        end

      json(conn, %{
        name: name,
        public_url: public_url,
        lan_url: lan_url,
        device_ip: device_ip,
        port: port,
        note: note
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

  defp public_url(resource) do
    share_name = get_in(resource.tunneld, ["share_names", "public"])

    case {share_name, Tunneld.Servers.Zrok.get_root_domain()} do
      {nil, _} -> nil
      {_, {:ok, domain}} -> "https://#{share_name}.#{domain}"
      _ -> nil
    end
  end

  defp extract_port(resource) do
    case resource.pool do
      [%{"port" => port} | _] when is_binary(port) -> String.to_integer(port)
      [%{"port" => port} | _] when is_integer(port) -> port
      [port_str | _] when is_binary(port_str) ->
        case String.split(port_str, ":", parts: 2) do
          [_, port] -> String.to_integer(port)
          _ -> nil
        end
      _ -> nil
    end
  end

  defp mock?(), do: Application.get_env(:tunneld, :mock_data, false)
end

defmodule TunneldWeb.Live.Dashboard.Actions do
  @moduledoc """
  Action dispatcher for the dashboard.

  Maps action name strings from the UI (modal forms, buttons, schema actions)
  to the corresponding server-side function calls. Each action receives
  decoded data and an optional `parent` pid for sending messages back to
  the LiveView process.
  """

  alias Tunneld.Servers.{
    Devices,
    Wlan,
    Zrok,
    Resources,
    Services,
    Auth,
    Sqm
  }

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @doc """
  Execute a named action with the given data.

  Returns the result of the action or broadcasts an error for unknown actions.
  """
  def perform(action, data, parent) do
    data = decode_if_needed(data)

    case action do
      # Device management
      "revoke_release_ip" ->
        if mac = data["mac"], do: Devices.revoke_lease(mac)

      "allow_device_expose" ->
        if mac = data["mac"], do: Tunneld.Servers.ExposeAllowed.allow(mac)

      "revoke_device_expose" ->
        if mac = data["mac"], do: Tunneld.Servers.ExposeAllowed.revoke(mac)

      "add_device_tag" ->
        mac = data["mac"]
        raw = data["tag"] || ""

        raw
        |> String.split(~r/,\s*/, trim: true)
        |> Enum.each(fn t ->
          t = String.trim(t)
          if t != "", do: Tunneld.Servers.DeviceTags.add_tag(mac, t)
        end)

      "remove_device_tag" ->
        mac = data["mac"]
        tag = data["tag"]
        if mac && tag, do: Tunneld.Servers.DeviceTags.remove_tag(mac, tag)

      # Wireless networking
      "connect_to_wireless_network" ->
        Wlan.connect_with_pass(data["ssid"], data["password"])

      "disconnect_from_wireless_network" ->
        Wlan.disconnect()
        Process.send_after(parent, :delayed_scan, 3000)

      "scan_for_wireless_networks" ->
        send(parent, :scan_for_wireless_networks)

      # Zrok control plane
      "configure_disable_control_plane" ->
        Zrok.unset_api_endpoint()
        Resources.try_hibernate_shares()

      "configure_enable_control_plane" ->
        Zrok.set_api_endpoint(data["url"])

      # Zrok environment
      "configure_enable_environment" ->
        Zrok.enable_env(data["account_token"])
        Resources.try_init_local_shares()

      "configure_disable_environment" ->
        Zrok.disable_env()
        Resources.try_hibernate_shares()

      # Auth
      "revoke_login_creds" ->
        File.rm(Auth.path())
        send(parent, :revoke_login_creds)

      "logout" ->
        send(parent, :do_logout)

      # DNS
      "set_dns_server" ->
        ip = data["server"]
        Tunneld.Servers.DnsConfig.set_dns_server(ip)

      # Resources
      "add_share" ->
        Resources.add_share(data)

      "update_share" ->
        Resources.update_share(data, :resource)

      "configure_basic_auth" ->
        Resources.configure_basic_auth(data)

      "disable_basic_auth" ->
        Resources.disable_basic_auth(data["resource_id"])

      "get_private_token" ->
        Resources.get_private_token(data["resource_id"])

      "add_private_share" ->
        Resources.add_access(data)

      "toggle_share_access" ->
        payload = data |> Map.get("payload") |> decode_if_needed()
        %{"id" => id, "enable" => enable, "kind" => kind} = payload

        case kind do
          "host" -> Resources.toggle_share(id, enable)
          "access" -> Resources.toggle_access(id, enable)
          _ -> raise "Kind not found, make sure resource is setup with correct kind"
        end

      "remove_share" ->
        %{"id" => id, "kind" => kind} = data

        case kind do
          "host" -> Resources.remove_share(id)
          "access" -> Resources.remove_access(id)
          _ -> raise "Kind not found, make sure resource is setup with correct kind"
        end

        send(parent, :close_details)

      "tunneld_settings" ->
        Resources.update_share(data, :tunneld)

      # SQM
      "set_sqm" ->
        Sqm.set_sqm(data)

      # Mesh
      "mesh_sync" ->
        Tunneld.Servers.Mesh.sync_now()

      "disconnect_mesh" ->
        path = Path.join(Tunneld.Config.fs_root(), "mesh_config.json")

        config =
          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, existing} ->
                  Map.merge(existing, %{"enabled" => false})

                _ ->
                  %{"enabled" => false}
              end

            _ ->
              %{"enabled" => false}
          end

        Tunneld.Persistence.write_json(path, config)

        current_interval =
          Application.get_env(:tunneld, :mesh, [])
          |> Keyword.get(:poll_interval, 25_000)

        url = Map.get(config, "coordinator_url", "")
        token = Map.get(config, "token", "")
        node_name = Map.get(config, "node_name", "")

        Application.put_env(:tunneld, :mesh,
          coordinator_url: if(url != "", do: url, else: nil),
          token: if(token != "", do: token, else: nil),
          node_name: if(node_name != "", do: node_name, else: nil),
          enabled: false,
          poll_interval: current_interval
        )

        Tunneld.Servers.Mesh.reconfigure()

      # Device restart
      "restart_device" ->
        if @mock do
          require Logger
          Logger.info("Mock mode: would restart tunneld service")
        else
          System.cmd("sudo", ["systemctl", "restart", "tunneld"])
        end

      "disable_tunneld_service" ->
        if @mock do
          require Logger
          Logger.info("Mock mode: would disable tunneld services")
        else
          System.cmd("sudo", ["systemctl", "stop", "tunneld"])
          System.cmd("sudo", ["systemctl", "stop", "dnsmasq"])
        end

      "enable_tunneld_service" ->
        if @mock do
          require Logger
          Logger.info("Mock mode: would enable tunneld services")
        else
          System.cmd("sudo", ["systemctl", "start", "dnsmasq"])
          System.cmd("sudo", ["systemctl", "start", "tunneld"])
        end

      "check_updates" ->
        Tunneld.Servers.Updater.check_now()

      _ ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Action doesnt exist and cant be handled"
        })
    end
  end

  defp decode_if_needed(%{} = data), do: data

  defp decode_if_needed(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  defp decode_if_needed(_), do: %{}


end

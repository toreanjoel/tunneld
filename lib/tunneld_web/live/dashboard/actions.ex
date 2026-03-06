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
    Blocklist,
    Auth,
    Sqm
  }

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

      # Wireless networking
      "connect_to_wireless_network" ->
        Wlan.connect_with_pass(data["ssid"], data["password"])

      "disconnect_from_wireless_network" ->
        Wlan.disconnect()
        Process.send_after(parent, :delayed_scan, 3000)

      "scan_for_wireless_networks" ->
        send(parent, :scan_for_wireless_networks)

      # WebAuthn
      "configure_web_authn" ->
        send(parent, :configure_web_authn)

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

      # Blocklist
      "update_blocklist" ->
        Blocklist.update()

      # Resources
      "add_share" ->
        Resources.add_share(data)

      "update_share" ->
        Resources.update_share(data, :resource)

      "configure_basic_auth" ->
        Resources.configure_basic_auth(data)

      "disable_basic_auth" ->
        Resources.disable_basic_auth(data["resource_id"])

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

      # Services
      "restart_service" ->
        service = Services.find_service(data["id"])
        if service, do: Services.restart_service(service)

      "refresh_service_logs" ->
        Services.get_service_logs(data["id"])

      # SQM
      "set_sqm" ->
        Sqm.set_sqm(data)

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

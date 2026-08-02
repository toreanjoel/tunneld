defmodule TunneldWeb.Live.Dashboard.Actions do
  @moduledoc """
  Action dispatcher for the dashboard.

  Maps action name strings from the UI (modal forms, buttons, schema actions)
  to the corresponding server-side function calls. Each action receives
  decoded data and an optional `parent` pid for sending messages back to
  the LiveView process.
  """

  alias Tunneld.Servers.{Devices, Resources, Auth}

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

      "remove_share" ->
        %{"id" => id} = data
        Resources.remove_share(id)
        send(parent, :close_details)

      "tunneld_settings" ->
        Resources.update_share(data, :resource)

      # Machines
      "enroll_machine" ->
        Tunneld.Machines.enroll(data)

      "create_container" ->
        id = data["machine_id"]

        spec = %{
          "name" => data["name"],
          "image" => data["image"],
          "type" => data["type"] || "container",
          "network" => data["network"] || "bridge",
          "cpu" => data["cpu"],
          "memory" => data["memory"],
          "ports" => data["ports"] || []
        }

        Tunneld.Machines.create_container(id, spec)

      "expose_container" ->
        Tunneld.Machines.Expose.expose(data["machine_id"], data["container"], data["port"])

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
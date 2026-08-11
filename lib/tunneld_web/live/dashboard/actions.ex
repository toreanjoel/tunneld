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
      "revoke_release_ip" ->
        if mac = data["mac"] do
          Devices.revoke_lease(mac)
          Devices.sync_now()
        end

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

        Devices.sync_now()

      "remove_device_tag" ->
        mac = data["mac"]
        tag = data["tag"]

        if mac && tag do
          Tunneld.Servers.DeviceTags.remove_tag(mac, tag)
          Devices.sync_now()
        end

      "revoke_login_creds" ->
        File.rm(Auth.path())
        send(parent, :revoke_login_creds)

      "logout" ->
        send(parent, :do_logout)

      "set_dns_server" ->
        ip = data["server"]
        Tunneld.Servers.DnsConfig.set_dns_server(ip)

      "add_share" ->
        Resources.add_share(data)

      "publish_resource" ->
        publish_resource(data)

      "update_share" ->
        Resources.update_share(data, :resource)

      "remove_share" ->
        %{"id" => id} = data
        Resources.remove_share(id)
        send(parent, :close_details)

      "tunneld_settings" ->
        Resources.update_share(data, :resource)

      "remove_machine" ->
        %{"id" => id} = data
        Tunneld.Machines.remove(id)
        send(parent, :close_details)

      "enroll_machine" ->
        Tunneld.Machines.enroll(data)

      "add_pool_member" ->
        id = data["id"]
        backend = data["backend"]

        case Tunneld.Servers.Resources.fetch_shares() |> Enum.find(&(&1.id == id)) do
          nil ->
            {:error, "resource not found"}

          resource ->
            pool = (resource.pool || []) ++ [backend]
            Tunneld.Servers.Resources.update_share(%{"id" => id, "pool" => pool}, :resource)
            {:ok, %{id: id, pool: pool}}
        end

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

  # Publishing is a remote install + config push, so it is reported the way
  # enrollment is: the parts that worked, and the one part the operator must do
  # themselves. It never claims the service is reachable - only `verify/1`,
  # which actually fetches the URL from the gateway's own uplink, can say that.
  defp publish_resource(%{"id" => id, "machine_id" => machine_id} = data) do
    resource = Resources.fetch_shares() |> Enum.find(&(&1.id == id))

    with {:ok, machine} <- Tunneld.Machines.get(machine_id),
         false <- is_nil(resource),
         {:ok, record} <-
           Tunneld.Publish.publish(
             %{"id" => resource.id, "name" => resource.name},
             machine,
             data["port"]
           ) do
      Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
        type: :info,
        message: "#{resource.name} published on #{record["machine_name"]} at #{record["url"]}"
      })

      Phoenix.PubSub.broadcast(Tunneld.PubSub, "publish:steps", {:publish_steps, record})
    else
      {:error, :invalid_port} ->
        notify_error("Port must be a number between 1 and 65535")

      true ->
        notify_error("Resource not found")

      {:error, reason} ->
        notify_error("Could not publish: #{inspect(reason)}")
    end
  end

  defp publish_resource(_), do: notify_error("Pick a machine and a port")

  defp notify_error(message) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{type: :error, message: message})
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

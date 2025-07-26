defmodule TunneldWeb.Plugs.AuthedDevice do
  @moduledoc """
  We check if the given device is authorized to access the controller CLI access
  """
  import Plug.Conn

  @doc """
  Initialize the plug with options
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    ip = extract_ip(conn)
    auth_check = authorized_ips(ip)

    if not Enum.empty?(auth_check) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{error: "Unauthorized device"})
      |> halt()
    end
  end

  defp extract_ip(conn) do
    conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
  end

  # Check if the current device has been authorized to get access to the internet
  # NOTE: Ideally we can assume and also there could be a separate property to know the device is authorized
  defp authorized_ips(ip) do
    # Do a call here to get the devices that are authorized
    # We should be calling the server but calling the filesystem rather and not relying on offeset limits
    # These limits are there if we take into account the device count support on the hardware
    {_, items} = Tunneld.Servers.Whitelist.read_file()

    items
      |> Enum.filter(fn i ->
        i["ip"] === ip and i["status"] === "granted"
      end)
  end
end

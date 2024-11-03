defmodule SentinelWeb.Plugs.SetIp do
  @moduledoc """
  Add the IP address of the client to the session
  """
  import Plug.Conn

  @doc """
  Initialize the plug with options
  """
  def init(opts), do: opts

  @doc """
  We get the user IP address and assign it to the session
  """
  def call(conn, _opts) do
    # Store the IP address in the session for tracking
    add_ip_to_session(conn)
  end

  # Store the IP address in the session for tracking
  defp add_ip_to_session(conn) do
    ip = extract_ip(conn)
    put_session(conn, :ip, ip)
  end

  # Extract the IP address as a string
  defp extract_ip(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end
end

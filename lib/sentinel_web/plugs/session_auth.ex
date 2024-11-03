defmodule SentinelWeb.Plugs.SessionAuth do
  @moduledoc """
  Authenticate the user session and check if the user is authorized to access the resource.
  """

  import Plug.Conn
  alias Sentinel.Servers.Session

  @doc """
  Initialize the plug with the options
  """
  def init(opts), do: opts

  @doc """
  Check the user and if they are authorized - return relevant resource
  """
  def call(conn, _opts) do
    conn = add_ip_to_session(conn)

    # This way we make sure the user cant access the resource
    if has_session?(conn) do
      # Create the session (to update the TTL and replace)
      Session.create(extract_ip(conn))
      conn
        |> assign(:current_user, Session.get(conn.remote_ip))

    else
      conn
      |> resp(401, "UNAUTHORIZED")
    end
  end

  # Check the user has a session or not
  defp has_session?(conn) do
    ip = extract_ip(conn)
    {status, _result} = Session.get(ip)
    if status == :ok, do: true, else: false
  end

  # The updated session with the ip address
  defp add_ip_to_session(conn) do
    ip = extract_ip(conn)
    put_session(conn, :ip, ip)
  end

  # Extract the ip address from the conn as a str
  defp extract_ip(conn) do
    conn.remote_ip
      |> Tuple.to_list()
      |> Enum.join(".")
  end
end

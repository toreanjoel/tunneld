defmodule TunneldWeb.Plugs.SetClientId do
  @moduledoc """
  Ensure each device has a unique client_id stored in the session.
  """
  import Plug.Conn

  @doc """
  Initialize the plug with options
  """
  def init(opts), do: opts

  @doc """
  Generate a client_id if one does not exist and store it in the session
  """
  def call(conn, _opts) do
    case get_session(conn, :client_id) do
      nil -> put_session(conn, :client_id, UUID.uuid4())
      _ -> conn
    end
  end
end

defmodule TunneldWeb.Plugs.CheckProtocol do
  @moduledoc """
  Check the protocol request that came to the gateway.
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
    IO.inspect(conn, label: "CONN _ PROTOCOL CHECK")
    conn
  end
end

defmodule TunneldWeb.Plugs.CheckProtocol do
  @moduledoc """
  Check the protocol request that came to the gateway.
  """
  @doc """
  Initialize the plug with options
  """
  def init(opts), do: opts

  @doc """
  Pass through — protocol checking is not yet implemented.
  """
  def call(conn, _opts) do
    conn
  end
end

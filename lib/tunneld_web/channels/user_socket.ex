defmodule TunneldWeb.UserSocket do
  @moduledoc """
  Phoenix socket for the exec terminal channel.

  Carries the session so the channel can enforce admin auth on connect.
  """
  use Phoenix.Socket


  def connect(%{"client_id" => client_id}, socket, _connect_info) do
    if client_id && Tunneld.Servers.Session.valid?(client_id) do
      {:ok, assign(socket, :client_id, client_id)}
    else
      :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  def id(_socket), do: nil
end
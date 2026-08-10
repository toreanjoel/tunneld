defmodule TunneldWeb.UserSocket do
  @moduledoc """
  Phoenix socket for the exec terminal channel.

  Auth comes from the signed, HttpOnly session cookie via `connect_info`, NOT
  from socket params. The endpoint already supplies it:

      socket "/ws", TunneldWeb.UserSocket,
        websocket: [connect_info: [session: @session_options]]

  An earlier version read `client_id` from a socket param that the frontend tried
  to lift out of `document.cookie`. That could never work - the session cookie is
  HttpOnly, so JS reads "" - and it would also have meant exposing a credential
  that grants a root shell to any script on the page. Reading it server-side is
  both correct and strictly safer.
  """
  use Phoenix.Socket

  channel "exec:*", TunneldWeb.ExecChannel

  @impl true
  def connect(_params, socket, %{session: %{"client_id" => client_id}})
      when is_binary(client_id) and client_id != "" do
    if Tunneld.Servers.Session.valid?(client_id) do
      {:ok, assign(socket, :client_id, client_id)}
    else
      :error
    end
  end

  @impl true
  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.client_id}"
end

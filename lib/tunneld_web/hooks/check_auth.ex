defmodule TunneldWeb.Hooks.CheckAuth do
  @moduledoc """
  This module is responsible for requiring authentication for the user and managing redirects based on access.
  """

  import Phoenix.LiveView
  alias TunneldWeb.Router.Helpers, as: Routes
  alias Tunneld.Servers.Session

  @doc """
  Mount the hook and check against the relevant views.
  """
  def on_mount(:default, _params, session, socket) do
    check_blocked_routes(session, socket)
  end

  # Redirect if the user is authenticated on public routes
  defp check_blocked_routes(session, socket)
       when socket.view in [TunneldWeb.Live.Login, TunneldWeb.Live.NotFound] do
    case Session.valid?(session["client_id"]) do
      true ->
        {:halt, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}

      false ->
        {:cont, socket}
    end
  end

  # Redirect to login for private routes if the user is unauthenticated
  defp check_blocked_routes(session, socket) do
    case Session.valid?(session["client_id"]) do
      true ->
        Session.renew(session["client_id"])
        {:cont, socket}

      false ->
        {:halt, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Login))}
    end
  end
end

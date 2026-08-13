defmodule TunneldWeb.Hooks.CheckAuth do
  @moduledoc """
  This module is responsible for requiring authentication for the user and managing redirects based on access.
  """

  import Phoenix.LiveView
  alias TunneldWeb.Router.Helpers, as: Routes
  alias Tunneld.Servers.Session

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
    client_id = session["client_id"]

    case Session.valid?(client_id) do
      true ->
        Session.renew(client_id)
        {:cont, renew_on_activity(socket, client_id)}

      false ->
        {:halt, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Login))}
    end
  end

  # The auth session was renewed on mount only. A LiveView mounts once and then
  # lives for hours, so an operator who kept the dashboard open let the session
  # lapse without noticing: every LiveView interaction still worked (events are
  # not auth-checked once mounted) but anything that authenticates afresh was
  # refused. The terminal is the visible case - `/ws` checks
  # `Session.valid?/1` at connect and answers 403, which the browser can only
  # report as "Socket connection failed".
  #
  # Renew on interaction instead. Activity keeps the session alive; a genuinely
  # idle tab still expires on schedule.
  defp renew_on_activity(socket, client_id) do
    attach_hook(socket, :renew_auth_session, :handle_event, fn _event, _params, socket ->
      Session.renew(client_id)
      {:cont, socket}
    end)
  end
end

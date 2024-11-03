defmodule SentinelWeb.Hooks.CheckAuth do
  @moduledoc """
  This module is responsible for requiring authentication for the user and managing redirects based on access.
  """

  import Phoenix.LiveView
  alias SentinelWeb.Router.Helpers, as: Routes
  alias Sentinel.Servers.Session

  @doc """
  Mount the hook and check against the relevant views.
  """
  def on_mount(:default, _params, session, socket) do
    check_blocked_routes(session, socket)
  end

  # Redirect if the user is authenticated on public routes
  defp check_blocked_routes(session, socket) when socket.view in [SentinelWeb.Live.Login, SentinelWeb.Live.NotFound] do
    case Session.get(session["ip"]) do
      {:ok, _} ->
        Session.create(session["ip"])
        {:halt, push_navigate(socket, to: Routes.live_path(socket, SentinelWeb.Live.Dashboard))}

      _ ->
        {:cont, socket}
    end
  end

  # Redirect to login for private routes if the user is unauthenticated
  defp check_blocked_routes(session, socket) do
    case Session.get(session["ip"]) do
      {:ok, _} ->
        Session.create(session["ip"])
        {:cont, socket}

      _ ->
        {:halt, push_navigate(socket, to: Routes.live_path(socket, SentinelWeb.Live.Login))}
    end
  end
end

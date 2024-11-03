defmodule SentinelWeb.Hooks.CheckAuth do
  @moduledoc """
  This module is responsible for requiring authentication for the user
  """
  import Phoenix.LiveView
  alias SentinelWeb.Router.Helpers, as: Routes
  alias Sentinel.Servers.Session

  @doc """
  Mount the hook and check against the relevant views
  """
  def on_mount(:default, _params, session, socket) do
    check_blocked_routes(session, socket)
  end

  # Redirect if the user is authed on public routes
  defp check_blocked_routes(session, socket) when socket.view in [SentinelWeb.Live.Login, SentinelWeb.Live.NotFound] do
    {status, _} = Session.get(session["ip"])
    case status === :ok do
      true ->
        Session.create(session["ip"])
        {:halt, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Dashboard))}

      _ ->
        {:cont, socket}
    end
  end

  # Redirect and check auth for the request to a route that is private
  defp check_blocked_routes(session, socket) do
    {status, _} = Session.get(session["ip"])
    case status === :ok do
      true ->
        Session.create(session["ip"])
        {:cont, socket}

      _ ->
        {:halt, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
    end
  end
end

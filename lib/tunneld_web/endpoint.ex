defmodule TunneldWeb.Endpoint do
  @moduledoc """
  Phoenix HTTP endpoint for the Tunneld dashboard. Uses the Bandit adapter.
  Serves static assets, LiveView websockets, and the browser session.
  """
  use Phoenix.Endpoint, otp_app: :tunneld

  @session_options [
    store: :cookie,
    key: "_tunneld_key",
    signing_salt: "e9ruVTpn",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:uri, :peer_data, session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  socket "/ws", TunneldWeb.UserSocket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :tunneld,
    gzip: false,
    only: TunneldWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TunneldWeb.Router
end

defmodule SentinelWeb.CaptivePortalController do
  use SentinelWeb, :controller

  # Called for GET /generate_204
  def force_captive_portal(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, """
    <html>
      <head><title>Captive Portal</title></head>
      <body>
        <p>Please sign in to access the internet.</p>
      </body>
    </html>
    """)
  end
end

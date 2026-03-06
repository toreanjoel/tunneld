defmodule TunneldWeb.HealthController do
  @moduledoc """
  Simple health check endpoint for monitoring.

  Returns 200 with basic status info when the application is running.
  """
  use TunneldWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok", version: Application.spec(:tunneld, :vsn) |> to_string()})
  end
end

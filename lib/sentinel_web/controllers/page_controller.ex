defmodule SentinelWeb.PageController do
  use SentinelWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end
end

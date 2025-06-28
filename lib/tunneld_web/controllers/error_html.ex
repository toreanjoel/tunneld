defmodule TunneldWeb.ErrorHTML do
  use TunneldWeb, :html

  # minimal 404
  def render("404.html", _assigns) do
    "<h1>404 — Not Found</h1>"
  end

  # minimal 500
  def render("500.html", _assigns) do
    "<h1>500 — Internal Server Error</h1>"
  end

  # fallback
  def template_not_found(_template, assigns) do
    render("500.html", assigns)
  end
end

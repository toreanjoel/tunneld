defmodule TunneldWeb.ErrorHTML do
  @moduledoc """
  The error pages that we will be used when there is issues on the request
  This does require updates for better UI rendering
  """
  use TunneldWeb, :html

  # minimal 404
  def render("404.html", _assigns) do
    "404 — Not Found"
  end

  # minimal 500
  def render("500.html", _assigns) do
    "500 — Internal Server Error"
  end

  # fallback
  def template_not_found(_template, assigns) do
    render("500.html", assigns)
  end
end

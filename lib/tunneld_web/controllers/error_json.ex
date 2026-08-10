defmodule TunneldWeb.ErrorJSON do
  @moduledoc """
  The error pages that we will be used when there is issues on the request
  This does require updates for responses
  """

  def render("404.json", _assigns) do
    %{errors: %{detail: "Not Found"}}
  end

  def render("500.json", _assigns) do
    %{errors: %{detail: "Internal Server Error"}}
  end

  def render(template, _assigns) do
    status = Phoenix.Controller.status_message_from_template(template)
    %{errors: %{detail: status}}
  end
end

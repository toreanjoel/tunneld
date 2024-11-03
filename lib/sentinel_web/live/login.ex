defmodule SentinelWeb.Live.Login do
  @moduledoc """
  Login page
  """
  alias Sentinel.Servers.Session
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Auth, Session}
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the login page and the session data for the client
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    # Initialize form data as a map - TODO: change this to a struct with ecto?
    form_data = %{"user" => "", "pass" => ""}

    # Convert the map to a form struct
    form = Phoenix.Component.to_form(form_data)

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(form: form)

    # Assign the form to the socket
    {:ok, socket}
  end

  @doc """
  Render the login form
  """
  def render(assigns) do
    ~H"""
    <.simple_form for={@form} id="login_form" phx-submit="login">
      <.input field={@form[:user]} label="Name" />
      <.input field={@form[:pass]} label="Password" type="password" />
      <:actions>
        <.button>Login</.button>
      </:actions>
    </.simple_form>
    """
  end

  @doc """
  Handle form validation on input change
  """
  def handle_event("login", %{"user" => user, "pass" => pass}, socket) do
    {_status, auth} = Auth.read_file()

    if user == auth["user"] and Bcrypt.verify_pass(pass, auth["pass"]) do
      Session.create(socket.assigns.ip)

      {:noreply,
       socket
       |> put_flash(:info, "Logged In!")
       |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Dashboard))}
    else
      {:noreply, socket |> put_flash(:error, "Invalid Credentials")}
    end
  end

  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end
end

defmodule SentinelWeb.Live.Login do
  @moduledoc """
  Login page
  """
  alias Sentinel.Servers.Session
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Auth, Session}
  alias SentinelWeb.Router.Helpers, as: Routes

  # Redirect the user to the dashboard if they are already logged in
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  Initialize the login page and the session data for the client
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "modal:form:action")
    end

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(:info_content, "127.0.0.1")

    # Assign the form to the socket
    {:ok, socket}
  end

  @doc """
  Render the login form
  """
  def render(assigns) do
    ~H"""
    <!-- Login wrapper -->
    <div class="flex flex-col bg-secondary lg:flex-row min-h-screen sm:height-screen p-2">
      <!-- Overview wrapper -->
      <div class="bg-primary relative hidden text-white lg:w-3/5 w-full lg:flex flex-col items-center justify-center p-8 rounded-lg">
        <%!-- backgroud grid --%>
        <div class="absolute inset-0 bg-grid pointer-events-none"></div>

        <div class="grow" />
        <div class="text-center grow">
          <span class="text-xs bg-gray-600 font-bold px-[10px] p-[5px] rounded">
            <%= @info_content %>
          </span>
          <h1 class="text-3xl font-bold my-4">sentinel.local</h1>
        </div>
      </div>


      <!-- Form wrapper -->
      <div class="lg:w-2/5 w-full flex items-center justify-center p-8">
        <%!-- <.simple_form for={@form} id="login_form" phx-submit="login" class="w-full max-w-sm">
          <h1 class="text-3xl font-bold mb-4 text-center">sentinel.local</h1>
          <.input field={@form[:user]} label="Name" class="mb-4" />
          <.input field={@form[:pass]} label="Password" type="password" class="mb-6" />
          <:actions>
            <.button class="w-full">Login</.button>
          </:actions>
        </.simple_form> --%>
          <!-- Login Form -->
          <div class="w-full max-w-sm">
            <.live_component
              id={DateTime.utc_now()}
              module={SentinelWeb.Live.Components.JsonSchemaRenderer}
              schema={Sentinel.Schema.Login.data()}
              action="login"
            />
          </div>
      </div>
    </div>
    """
  end

  @doc """
  Handle form validation on input change
  """
  # def handle_event("login", %{"user" => user, "pass" => pass}, socket) do
  #   can_login = auth_check(%{ user: user, pass: pass}, socket)
  #   if can_login do
  #     Session.create(socket.assigns.ip)

  #     {:noreply,
  #      socket
  #      |> put_flash(:info, "Logged In!")
  #      |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.DashboardV2))}
  #   else

  #     socket = socket |> put_flash(:error, "Invalid Credentials")
  #     # We clear the flash after 3 seconds
  #     Process.send_after(self(), :clear_flash, 3000)
  #     {:noreply, socket}
  #   end

  # end

  #
  # clear the flash messages
  #
  @spec handle_info(atom(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

    #
  # handle the actions from the schema form
  #
  def handle_info(%{action: action, data: data}, socket) do
    case action do
      "login" ->
        send(self(), %{"can_login" => auth_check(data, socket)})
        _ ->
        socket = socket |> put_flash(:error, "Invalid Credentials")
        # We clear the flash after 3 seconds
        Process.send_after(self(), :clear_flash, 3000)
        {:noreply, socket}
    end

    {:noreply, socket}
  end

  #
  # Auth Check - user against configured details
  #
  @spec auth_check(String.t(), String.t()) :: boolean()
  defp auth_check(%{"name" => user, "password" => pass}, socket) do
    {_status, auth} = Auth.read_file()

    if user == auth["user"] and Bcrypt.verify_pass(pass, auth["pass"]) do
      Session.create(socket.assigns.ip)
      true
    else
      false
    end
  end
end

defmodule TunneldWeb.Live.Login do
  @moduledoc """
  Login page
  """
  alias Tunneld.Servers.Session
  use TunneldWeb, :live_view
  alias Tunneld.Servers.{Auth, Session}
  alias TunneldWeb.Router.Helpers, as: Routes

  # Redirect the user to the dashboard if they are already logged in
  on_mount TunneldWeb.Hooks.CheckAuth

  @doc """
  Initialize the login page and the session data for the client
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "modal:form:action")
    end

    # TODO: check the password file exists or show a form to create
    # Update the info content here
    type = if Tunneld.Servers.Auth.file_exists?(), do: :login, else: :signup

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:ip, ip)
      |> assign(:type, type)
      |> assign(:info_content, Application.get_env(:tunneld, :network)[:gateway] || nil)

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
          <span
            :if={not is_nil(@info_content)}
            class="text-xs bg-gray-600 font-bold px-[10px] p-[5px] rounded"
          >
            <%= @info_content %>
          </span>
          <h1 class="text-3xl font-bold my-4">tunneld.local</h1>
        </div>
      </div>

      <div class="lg:w-2/5 w-full flex items-center justify-center p-8">
        <div :if={@type === :login} class="w-full max-w-sm">
          <h1 class="text-3xl text-white font-bold mb-4 text-center">Login</h1>
          <!-- Login Form -->
          <.live_component
            id={DateTime.utc_now()}
            module={TunneldWeb.Live.Components.JsonSchemaRenderer}
            schema={Tunneld.Schema.Login.data()}
            loading={@loading}
            action="login"
          />
        </div>
        <div :if={@type === :signup} class="w-full max-w-sm">
          <h1 class="text-3xl text-white font-bold mb-4 text-center">Register</h1>
          <!-- signup Form -->
          <.live_component
            id={DateTime.utc_now()}
            module={TunneldWeb.Live.Components.JsonSchemaRenderer}
            schema={Tunneld.Schema.Signup.data()}
            loading={@loading}
            action="signup"
          />
        </div>
      </div>
    </div>
    """
  end

  #
  # clear the flash messages
  #
  @spec handle_info(atom(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  #
  # Check if the user details are correct to log into the system
  #
  def handle_info(%{can_login: can_login}, socket) do
    if can_login do
      Session.create(socket.assigns.ip)
      send(self(), %{loading: false})

      {:noreply,
       socket
       |> push_navigate(to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
    else
      socket = socket |> put_flash(:error, "Invalid Credentials")
      # We clear the flash after 3 seconds
      Process.send_after(self(), :clear_flash, 3000)
      send(self(), %{loading: false})
      {:noreply, socket}
    end
  end

  #
  # Check if the user can sign up
  # We need to let the user know the signup is good an show login
  #
  def handle_info(%{can_signup: can_signup}, socket) do
    if can_signup do
      send(self(), %{loading: false})
      # Here we need to return the socket with the login state
      # here we put a flash to let the user know it was successful
      socket = socket |> put_flash(:info, "User successfully created!") |> assign(:type, :login)

      {:noreply, socket}
    else
      socket = socket |> put_flash(:error, "Make sure the passwords match")
      # We clear the flash after 3 seconds
      Process.send_after(self(), :clear_flash, 3000)
      send(self(), %{loading: false})
      {:noreply, socket}
    end
  end

  #
  # async handle the submit and loading of the form
  #
  def handle_info(%{action: _action, data: _data} = payload, socket) do
    send(self(), %{loading: true})
    send(self(), %{action: payload})
    {:noreply, socket}
  end

  #
  # Try to authorize the user - login action for the json form
  #
  def handle_info(%{action: %{action: "login", data: data}}, socket) do
    # We dont validate with the schema as we dont want to give hints away
    send(self(), %{can_login: auth_check(data, socket)})
    {:noreply, socket}
  end

  #
  # Try to signup - signup and check the details
  #
  def handle_info(%{action: %{action: "signup", data: data}}, socket) do
    send(self(), %{can_signup: signup_check(data, socket)})
    {:noreply, socket}
  end

  #
  # toggle loading
  #
  def handle_info(%{loading: loading}, socket) do
    {:noreply, socket |> assign(loading: loading)}
  end

  #
  # Auth Check - user against configured details
  #
  @spec auth_check(map(), Phoenix.LiveView.Socket.t()) :: boolean()
  defp auth_check(%{"name" => user, "password" => pass}, socket) do
    {_status, auth} = Auth.read_file()

    if user == auth["user"] and Bcrypt.verify_pass(pass, auth["pass"]) do
      Session.create(socket.assigns.ip)
      true
    else
      false
    end
  end

  #
  # Signup details check - Check if the user is allowed to sign up
  #
  @spec signup_check(map(), Phoenix.LiveView.Socket.t()) :: boolean()
  defp signup_check(
         %{"name" => user, "password" => p1, "confirm_password" => p2},
         _
       ) do
    if p1 === p2 do
      # Check the creation of the file if there is an error or successful
      {status, _} = Tunneld.Servers.Auth.create_file(user, p1)

      case status do
        :ok -> true
        _ -> false
      end
    else
      false
    end
  end
end

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

    uri_info = get_connect_info(socket, :uri)
    host = uri_info && URI.parse(uri_info) |> Map.get(:host)
    gateway_domain = System.get_env("CF_DOMAIN") || "tunneld.local"
    gateway_ip = Application.get_env(:tunneld, :network)[:gateway]

    has_webauthn? = Tunneld.Servers.Auth.has_webauthn?()
    connected_via_gateway_domain = host == gateway_domain

    # Fix: Don't crash if any value is nil
    show_form = not has_webauthn? or not connected_via_gateway_domain
    show_webauthn = has_webauthn? and connected_via_gateway_domain

    type =
      if Tunneld.Servers.Auth.file_exists?() do
        :login
      else
        :signup
      end

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:ip, ip)
      |> assign(:type, type)
      |> assign(:info_content, gateway_ip)
      |> assign(:show_form, show_form)
      |> assign(:show_webauthn, show_webauthn)

    {:ok, socket}
  end

  @doc """
  Render the login form
  """
  def render(assigns) do
    ~H"""
    <!-- Login wrapper -->
    <div
      id="auth"
      phx-hook="Auth"
      class="flex flex-col bg-secondary lg:flex-row min-h-screen sm:height-screen p-2"
    >
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
        <div class="text-sm text-gray-1">
          <a href="https://github.com/toreanjoel/tunneld" target="_blank">
            Made with ☕ | <span class="underline"> self-host your own tunneld instance </span>
          </a>
        </div>
      </div>

      <div class="lg:w-2/5 w-full flex flex-col items-center justify-center p-8">
        <div :if={@show_form and @type === :login} class="w-full max-w-sm">
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
        <div :if={@show_form and @type === :signup} class="w-full max-w-sm">
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
        <div class="py-2" />
        <%!-- We need to only show the option for this auth if the artifact for the gateway is exposed? --%>
        <div :if={@show_webauthn} class="mt-4 text-center flex flex-col text-gray-500 gap-2">
          <h1 class="text-lg text-white font-bold mb-4 text-center">Login (WebAuthn)</h1>
          <button phx-click="trigger_webauthn_login">
            <.icon name="hero-finger-print" class="h-14 w-14" />
          </button>
          <div class="text-sm text-gray-1">
            Authorized device access
          </div>
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
  # trigger the login challenge to compare against the current auth file
  #
  def handle_event("trigger_webauthn_login", _params, socket) do
    with {:ok, auth} <- Tunneld.Servers.Auth.read_file(),
         %{"webauthn" => webauthn} <- auth do
      challenge = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      # Save challenge temporarily for comparison (or add it to session)
      socket = assign(socket, :webauthn_challenge, challenge)

      public_key_options = %{
        challenge: challenge,
        timeout: 60_000,
        allowCredentials: [
          %{
            id: webauthn["rawId"],
            type: "public-key",
            transports: ["usb", "nfc", "ble", "internal"]
          }
        ],
        userVerification: "preferred"
      }

      socket =
        socket
        |> assign(:webauthn_challenge, challenge)
        |> push_event("start_webauthn_login", %{publicKeyOptions: public_key_options})

      {:noreply, socket}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "No WebAuthn credential available")}
    end
  end

  #
  # Log in and setup session for the user
  #
  def handle_event("webauthn_login_complete", %{"id" => id}, socket) do
    with {:ok, auth} <- Tunneld.Servers.Auth.read_file(),
         %{"webauthn" => webauthn} <- auth,
         true <- id == webauthn["id"] do
      Session.create(socket.assigns.ip)

      {:noreply,
       socket
       |> push_navigate(to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "WebAuthn login failed")}
    end
  end

  #
  # Error completing the WebAuthn registration
  #
  def handle_event("webauthn_login_error", %{"error" => err}, socket) do
    {:noreply, socket |> put_flash(:error, err)}
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

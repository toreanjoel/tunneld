defmodule TunneldWeb.Live.Login do
  @moduledoc """
  Login page
  """
  alias Tunneld.Servers.Session
  use TunneldWeb, :live_view
  alias Tunneld.Servers.{Auth, Session}
  alias TunneldWeb.Router.Helpers, as: Routes

  on_mount TunneldWeb.Hooks.CheckAuth

  @doc """
  Initialize the login page and the session data for the client
  """
  def mount(_params, %{"client_id" => client_id} = _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "modal:form:action:#{client_id}")
    end

    uri_info = get_connect_info(socket, :uri)
    _host = uri_info && URI.parse(uri_info) |> Map.get(:host)

    type =
      if Tunneld.Servers.Auth.file_exists?() do
        :login
      else
        :signup
      end

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:client_id, client_id)
      |> assign(:type, type)
      |> assign(:info_content, nil)

    {:ok, socket}
  end

  @doc """
  Render the login form
  """
  def render(assigns) do
    ~H"""
    <div id="auth" class="flex flex-col lg:flex-row min-h-screen">
      <div class="relative text-text-primary lg:w-3/5 w-full lg:flex flex-col items-center justify-center p-8 rounded-lg">
        <div class="absolute inset-0 bg-grid pointer-events-none"></div>

        <div class="grow" />
        <div class="text-center grow flex flex-col items-center justify-center">
          <h1 class="text-4xl font-semibold text-text-primary mb-2 -tracking-[0.01em]">Tunneld</h1>
          <p class="text-sm text-text-secondary font-light tracking-[0.02em]">A subnet in your pocket.</p>
          <div class="text-xs text-text-tertiary font-mono mt-4">
            <%= Application.get_env(:tunneld, :metadata)[:device_id] || System.get_env("DEVICE_ID") %>
          </div>
        </div>
        <div class="text-sm text-text-secondary pb-4">
          <a href="https://github.com/toreanjoel/tunneld" target="_blank" class="hover:text-text-primary transition-colors">
            Made with ☕️ | by Torean
          </a>
        </div>
      </div>

      <div class="lg:w-2/5 w-full flex flex-col items-center justify-center p-8 bg-surface">
        <div :if={@type === :login} class="w-full max-w-sm">
          <h1 class="text-2xl text-text-primary font-medium mb-6 text-center -tracking-[0.01em]">Login</h1>
          <.live_component
            id={"login_#{DateTime.utc_now()}"}
            module={TunneldWeb.Live.Components.JsonSchemaRenderer}
            schema={Tunneld.Schema.data(:login)}
            loading={@loading}
            action="login"
            client_id={@client_id}
          />
        </div>
        <div :if={@type === :signup} class="w-full max-w-sm">
          <h1 class="text-2xl text-text-primary font-medium mb-6 text-center -tracking-[0.01em]">Register</h1>
          <.live_component
            id={"signup_#{DateTime.utc_now()}"}
            module={TunneldWeb.Live.Components.JsonSchemaRenderer}
            schema={Tunneld.Schema.data(:signup)}
            loading={@loading}
            action="signup"
            client_id={@client_id}
          />
        </div>
      </div>
    </div>
    """
  end

  @spec handle_info(atom(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  def handle_info(%{can_login: can_login}, socket) do
    if can_login do
      Session.create(socket.assigns.client_id)
      send(self(), %{loading: false})

      {:noreply,
       socket
       |> push_navigate(to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
    else
      socket = socket |> put_flash(:error, "Invalid Credentials")
      Process.send_after(self(), :clear_flash, 3000)
      send(self(), %{loading: false})
      {:noreply, socket}
    end
  end

  def handle_info(%{can_signup: can_signup}, socket) do
    if can_signup do
      send(self(), %{loading: false})
      Session.create(socket.assigns.client_id)

      {:noreply,
       socket
       |> push_navigate(to: Routes.live_path(socket, TunneldWeb.Live.Setup))}
    else
      socket = socket |> put_flash(:error, "Make sure the passwords match")
      Process.send_after(self(), :clear_flash, 3000)
      send(self(), %{loading: false})
      {:noreply, socket}
    end
  end

  def handle_info(%{action: _action, data: _data} = payload, socket) do
    send(self(), %{loading: true})
    send(self(), %{action: payload})
    {:noreply, socket}
  end

  def handle_info(%{action: %{action: "login", data: data}}, socket) do
    send(self(), %{can_login: auth_check(data, socket)})
    {:noreply, socket}
  end

  def handle_info(%{action: %{action: "signup", data: data}}, socket) do
    send(self(), %{can_signup: signup_check(data, socket)})
    {:noreply, socket}
  end

  def handle_info(%{loading: loading}, socket) do
    {:noreply, socket |> assign(loading: loading)}
  end

  @spec auth_check(map(), Phoenix.LiveView.Socket.t()) :: boolean()
  defp auth_check(%{"name" => user, "password" => pass}, socket) do
    {_status, auth} = Auth.read_file()

    if user == auth["user"] and Bcrypt.verify_pass(pass, auth["pass"]) do
      Session.create(socket.assigns.client_id)
      true
    else
      false
    end
  end

  @spec signup_check(map(), Phoenix.LiveView.Socket.t()) :: boolean()
  defp signup_check(
         %{"name" => user, "password" => p1, "confirm_password" => p2},
         _
       ) do
    if p1 === p2 do
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

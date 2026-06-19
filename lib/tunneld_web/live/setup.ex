defmodule TunneldWeb.Live.Setup do
  @moduledoc """
  First-run setup wizard shown after initial account creation.

  Guides the user through configuring the mesh relay coordinator. Tracked via
  an `onboarded` flag in auth.json so it only appears once.
  """

  use TunneldWeb, :live_view
  require Logger

  alias Tunneld.Servers.Auth
  alias TunneldWeb.Router.Helpers, as: Routes

  on_mount TunneldWeb.Hooks.CheckAuth

  def mount(_params, %{"client_id" => _client_id} = _session, socket) do
    if onboarded?() do
      {:ok, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "notifications")
      end

      mesh_preconfigured = mesh_configured?()

      socket =
        socket
        |> assign(:step, :mesh)
        |> assign(:mesh_configured, mesh_preconfigured)
        |> assign(:mesh_loading, false)

      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen bg-bg text-text-primary">
      <div class="flex-1 flex flex-col items-center justify-center p-6">
        <div class="w-full max-w-lg">
          <div class="text-center mb-8">
            <h1 class="text-3xl font-semibold mb-2 -tracking-[0.01em]">Setup Tunneld</h1>
            <p class="text-text-secondary text-sm">
              <%= step_description(@step) %>
            </p>
          </div>

          <div class="flex items-center justify-center gap-3 mb-8">
            <div class={step_dot(:mesh, @step)} />
          </div>

          <%= render_step(assigns) %>
        </div>
      </div>
    </div>
    """
  end

  defp render_step(%{step: :mesh} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div :if={@mesh_configured} class="flex flex-col items-center justify-center py-6 gap-3">
        <div class="w-12 h-12 rounded-full bg-green/10 flex items-center justify-center">
          <.icon name="hero-check" class="w-6 h-6 text-green" />
        </div>
        <div class="text-center">
          <div class="text-sm font-medium">Mesh relay configured</div>
          <div class="text-xs text-text-secondary mt-1">You can manage this from the dashboard</div>
        </div>
      </div>

      <div :if={@mesh_configured} class="flex gap-3 pt-4">
        <button phx-click="finish_setup" class="w-full p-3 rounded-lg bg-accent text-sm font-medium hover:bg-accent-light transition">
          Finish
        </button>
      </div>

      <div :if={not @mesh_configured} class="bg-surface rounded-lg p-4">
        <div class="text-sm text-text-secondary">
          Mesh networking connects this node to other tunneld instances through a relay.
          This step is optional - you can configure it later from the dashboard.
        </div>
      </div>

      <form :if={not @mesh_configured} phx-submit="configure_mesh" class="space-y-3">
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Relay URL</label>
          <input type="url" name="coordinator_url" placeholder="http://relay.example.com:4000" class="tunl-input" />
        </div>
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Token</label>
          <input type="password" name="token" placeholder="shared-secret" autocomplete="off" class="tunl-input" />
        </div>
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Node Name</label>
          <input type="text" name="node_name" placeholder="living-room-gateway" class="tunl-input" />
        </div>
        <button type="submit" disabled={@mesh_loading} class="w-full p-3 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 bg-accent hover:bg-accent-light disabled:opacity-50 disabled:cursor-wait">
          <svg :if={@mesh_loading} class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <%= if @mesh_loading, do: "Saving...", else: "Save Mesh Config" %>
        </button>
      </form>

      <div :if={not @mesh_configured} class="flex gap-3 pt-4">
        <button phx-click="finish_setup" class="w-full p-3 rounded-lg bg-accent text-sm font-medium hover:bg-accent-light transition">Skip & Finish</button>
      </div>
    </div>
    """
  end

  def handle_event("configure_mesh", %{
        "coordinator_url" => url,
        "token" => token,
        "node_name" => name
      }, socket) do
    url = String.trim(url)
    token = String.trim(token)
    name = String.trim(name)

    if url == "" or token == "" do
      {:noreply, put_flash(socket, :error, "Relay URL and token are required")}
    else
      config = %{
        "coordinator_url" => url,
        "token" => token,
        "node_name" => name,
        "enabled" => true
      }

      socket = assign(socket, :mesh_loading, true)

      path = Path.join(Tunneld.Config.fs_root(), "mesh_config.json")
      Tunneld.Persistence.write_json(path, config)

      current_interval =
        Application.get_env(:tunneld, :mesh, [])
        |> Keyword.get(:poll_interval, 25_000)

      Application.put_env(:tunneld, :mesh,
        coordinator_url: url,
        token: token,
        node_name: name,
        enabled: true,
        poll_interval: current_interval
      )

      Tunneld.Servers.Mesh.reconfigure()

      socket =
        socket
        |> put_flash(:info, "Mesh configuration saved")
        |> assign(:mesh_configured, true)

      {:noreply, socket}
    end
  end

  def handle_event("finish_setup", _, socket) do
    mark_onboarded()
    {:noreply, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
  end

  def handle_info(%{type: type, message: message}, socket) when type in [:info, :error] do
    mesh_success = socket.assigns.mesh_loading and type == :info
    socket = put_flash(socket, type, message)

    {:noreply,
     assign(socket,
       mesh_loading: false,
       mesh_configured: socket.assigns.mesh_configured || mesh_success
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp onboarded? do
    case Auth.read_file() do
      {:ok, data} -> Map.get(data, "onboarded", false)
      _ -> false
    end
  end

  defp mark_onboarded do
    case Auth.read_file() do
      {:ok, data} ->
        Tunneld.Persistence.write_json(Auth.path(), Map.put(data, "onboarded", true))

      _ ->
        :ok
    end
  end

  defp step_description(:mesh), do: "Configure mesh relay (optional)"

  defp step_dot(step, current) do
    base = "w-3 h-3 rounded-full transition"

    cond do
      step == current -> "#{base} bg-accent"
      step_index(step) < step_index(current) -> "#{base} bg-green"
      true -> "#{base} bg-text-tertiary"
    end
  end

  defp step_index(:mesh), do: 0

  defp mesh_configured? do
    path = Path.join(Tunneld.Config.fs_root(), "mesh_config.json")

    case Tunneld.Persistence.read_json(path) do
      {:ok, %{"enabled" => true, "coordinator_url" => url, "token" => token}}
        when is_binary(url) and url != "" and is_binary(token) and token != "" ->
        true

      _ ->
        false
    end
  end
end
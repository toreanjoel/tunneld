defmodule TunneldWeb.Live.Setup do
  @moduledoc """
  First-run setup wizard shown after initial account creation.

  Guides the user through connecting to Wi-Fi and configuring
  the overlay network. Tracked via an `onboarded` flag in auth.json
  so it only appears once.
  """
  use TunneldWeb, :live_view
  require Logger

  alias Tunneld.Servers.{Auth, Wlan, Zrok}
  alias TunneldWeb.Router.Helpers, as: Routes

  on_mount TunneldWeb.Hooks.CheckAuth

  def mount(_params, %{"client_id" => _client_id} = _session, socket) do
    if onboarded?() do
      {:ok, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "notifications")
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "status:internet")
      end

      mesh_preconfigured = mesh_configured?()

      socket =
        socket
        |> assign(:step, :wifi)
        |> assign(:scanning, false)
        |> assign(:connecting, false)
        |> assign(:networks, [])
        |> assign(:wifi_info, %{})
        |> assign(:internet, check_internet())
        |> assign(:zrok_loading, false)
        |> assign(:zrok_configured, false)
        |> assign(:env_loading, false)
        |> assign(:env_enabled, false)
        |> assign(:mesh_configured, mesh_preconfigured)
        |> assign(:mesh_loading, false)

      if connected?(socket), do: start_scan()

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
            <div class={step_dot(:wifi, @step)} />
            <div class="w-8 h-px bg-border" />
            <div class={step_dot(:zrok, @step)} />
            <div class="w-8 h-px bg-border" />
            <div class={step_dot(:mesh, @step)} />
          </div>

          <%= render_step(assigns) %>
        </div>
      </div>
    </div>
    """
  end

  defp render_step(%{step: :wifi} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div class={"flex items-center gap-3 p-4 rounded-lg #{if @internet, do: "bg-green/10 border border-green/30", else: "bg-surface"}"}>
        <div class={"w-3 h-3 rounded-full #{if @internet, do: "bg-green", else: "bg-text-tertiary"}"} />
        <div>
          <div class="text-sm font-medium">
            <%= if @internet, do: "Connected to internet", else: "Not connected" %>
          </div>
          <div :if={@wifi_info["ssid"]} class="text-xs text-text-secondary">
            Network: <%= @wifi_info["ssid"] %>
          </div>
        </div>
      </div>

      <button
        :if={!(@scanning and Enum.empty?(@networks))}
        phx-click="scan"
        disabled={@scanning}
        class="flex items-center justify-center gap-2 w-full p-3 rounded-lg transition bg-surface hover:bg-surface-2 cursor-pointer disabled:cursor-wait disabled:opacity-50 text-sm"
      >
        <svg :if={@scanning} class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
        <.icon :if={!@scanning} class="w-4 h-4" name="hero-arrow-path" />
        <span class="text-sm"><%= if @scanning, do: "Scanning...", else: "Scan for networks" %></span>
      </button>

      <div :if={@scanning and Enum.empty?(@networks)} class="flex flex-col items-center justify-center py-8 gap-2">
        <svg class="animate-spin h-6 w-6 text-text-secondary" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
        <span class="text-xs text-text-secondary">Scanning for networks...</span>
      </div>

      <div :if={!Enum.empty?(@networks)} class="space-y-2 max-h-64 overflow-y-auto system-scroll">
        <%= for network <- @networks do %>
          <% is_connected = @wifi_info["ssid"] == network.ssid %>
          <div
            class={"flex items-center justify-between p-3 rounded-lg cursor-pointer transition #{if is_connected, do: "bg-accent", else: "bg-surface hover:bg-surface-2"}"}
            phx-click={unless is_connected, do: "select_network"}
            phx-value-ssid={network.ssid}
            phx-value-open={to_string(network.open)}
          >
            <div class="flex items-center gap-3 min-w-0">
              <.icon class="w-4 h-4 flex-shrink-0" name={if network.open, do: "hero-lock-open", else: "hero-lock-closed"} />
              <div class="truncate">
                <div class="text-sm truncate"><%= network.ssid %></div>
                <div class="text-xs text-text-secondary"><%= network.signal %> dBm</div>
              </div>
            </div>
            <div :if={is_connected} class="text-xs bg-white/20 px-2 py-1 rounded">Connected</div>
          </div>
        <% end %>
      </div>

      <div :if={assigns[:selected_network]} class="bg-surface rounded-lg p-4 space-y-3">
        <div class="text-sm font-medium">Connect to "<%= @selected_network %>"</div>
        <form phx-submit="connect_wifi" class="space-y-3">
          <input type="hidden" name="ssid" value={@selected_network} />
          <input
            :if={!assigns[:selected_open]}
            type="password"
            name="password"
            placeholder="Password"
            autocomplete="off"
            class="tunl-input"
          />
          <div class="flex gap-2">
            <button type="button" phx-click="cancel_select" class="flex-1 p-3 rounded-lg bg-surface-2 text-sm hover:bg-border transition">
              Cancel
            </button>
            <button
              type="submit"
              disabled={@connecting}
              class="flex-1 p-3 rounded-lg text-sm transition flex items-center justify-center gap-2 bg-accent hover:bg-accent-light disabled:opacity-50 disabled:cursor-wait"
            >
              <svg :if={@connecting} class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
              <%= if @connecting, do: "Connecting...", else: "Connect" %>
            </button>
          </div>
        </form>
      </div>

      <div class="flex gap-3 pt-4">
        <button
          phx-click="next_step"
          class="flex-1 p-3 rounded-lg text-sm font-medium transition bg-accent hover:bg-accent-light disabled:bg-surface disabled:text-text-secondary"
        >
          <%= if @internet, do: "Next", else: "Skip (no internet)" %>
        </button>
      </div>
    </div>
    """
  end

  defp render_step(%{step: :zrok} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div :if={@zrok_configured and @env_enabled} class="flex flex-col items-center justify-center py-6 gap-3">
        <div class="w-12 h-12 rounded-full bg-green/10 flex items-center justify-center">
          <.icon name="hero-check" class="w-6 h-6 text-green" />
        </div>
        <div class="text-center">
          <div class="text-sm font-medium">Device enabled on overlay network</div>
          <div class="text-xs text-text-secondary mt-1">You can manage this from the dashboard</div>
        </div>
      </div>

      <div :if={@zrok_configured and @env_enabled} class="flex gap-3 pt-4">
        <button phx-click="finish_setup" class="w-full p-3 rounded-lg bg-accent text-sm font-medium hover:bg-accent-light transition">
          Finish
        </button>
      </div>

      <div :if={@zrok_configured and not @env_enabled} class="flex items-center gap-3 p-4 rounded-lg bg-green/10 border border-green/30">
        <div class="w-3 h-3 rounded-full bg-green" />
        <div class="text-sm font-medium">Control plane configured</div>
      </div>

      <form :if={@zrok_configured and not @env_enabled} phx-submit="enable_environment" class="space-y-3">
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Account Token</label>
          <input type="password" name="account_token" placeholder="Account token from your control plane" autocomplete="off" class="tunl-input" />
        </div>
        <button type="submit" disabled={@env_loading} class="w-full p-3 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 bg-accent hover:bg-accent-light disabled:opacity-50 disabled:cursor-wait">
          <svg :if={@env_loading} class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <%= if @env_loading, do: "Enabling device...", else: "Enable Device" %>
        </button>
      </form>

      <div :if={@zrok_configured and not @env_enabled} class="flex gap-3 pt-4">
        <button phx-click="prev_step" class="flex-1 p-3 rounded-lg bg-surface text-sm hover:bg-surface-2 transition">Back</button>
        <button phx-click="finish_setup" class="flex-1 p-3 rounded-lg bg-accent text-sm font-medium hover:bg-accent-light transition">Finish</button>
      </div>

      <div :if={not @zrok_configured} class="bg-surface rounded-lg p-4">
        <div class="text-sm text-text-secondary">
          Zrok enables secure tunnels to expose your local services to the internet
          without port forwarding. This step is optional — you can configure it later
          from the dashboard.
        </div>
      </div>

      <form :if={not @zrok_configured} phx-submit="configure_zrok" class="space-y-3">
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Control Plane URL</label>
          <input type="url" name="url" placeholder="https://zrok.example.com" class="tunl-input" />
        </div>
        <button type="submit" disabled={@zrok_loading} class="w-full p-3 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 bg-accent hover:bg-accent-light disabled:opacity-50 disabled:cursor-wait">
          <svg :if={@zrok_loading} class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <%= if @zrok_loading, do: "Configuring...", else: "Configure Control Plane" %>
        </button>
      </form>

      <div :if={not @zrok_configured} class="flex gap-3 pt-4">
        <button phx-click="prev_step" class="flex-1 p-3 rounded-lg bg-surface text-sm hover:bg-surface-2 transition">Back</button>
        <button phx-click="next_step" class="flex-1 p-3 rounded-lg bg-accent text-sm font-medium hover:bg-accent-light transition">Skip & Next</button>
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
          This step is optional — you can configure it later from the dashboard.
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
        <button phx-click="prev_step" class="flex-1 p-3 rounded-lg bg-surface text-sm hover:bg-surface-2 transition">Back</button>
        <button phx-click="finish_setup" class="flex-1 p-3 rounded-lg bg-accent text-sm font-medium hover:bg-accent-light transition">Skip & Finish</button>
      </div>
    </div>
    """
  end

  def handle_event("scan", _, socket) do
    start_scan()
    {:noreply, assign(socket, scanning: true)}
  end

  def handle_event("select_network", %{"ssid" => ssid, "open" => open}, socket) do
    socket =
      socket
      |> assign(:selected_network, ssid)
      |> assign(:selected_open, open == "true")

    {:noreply, socket}
  end

  def handle_event("cancel_select", _, socket) do
    {:noreply, socket |> assign(:selected_network, nil) |> assign(:selected_open, false)}
  end

  def handle_event("connect_wifi", %{"ssid" => ssid} = params, socket) do
    password = Map.get(params, "password", "")
    Wlan.connect_with_pass(ssid, password)

    socket =
      socket
      |> assign(:connecting, true)
      |> assign(:selected_network, nil)

    Process.send_after(self(), :check_connection, 5000)
    {:noreply, socket}
  end

  def handle_event("next_step", _, socket) do
    next =
      case socket.assigns.step do
        :wifi -> :zrok
        :zrok -> :mesh
        :mesh -> :mesh
      end

    {:noreply, assign(socket, :step, next)}
  end

  def handle_event("prev_step", _, socket) do
    prev =
      case socket.assigns.step do
        :wifi -> :wifi
        :zrok -> :wifi
        :mesh -> :zrok
      end

    {:noreply, assign(socket, :step, prev)}
  end

  def handle_event("configure_zrok", %{"url" => url}, socket) when url != "" do
    Zrok.set_api_endpoint(url)
    {:noreply, assign(socket, zrok_loading: true)}
  end

  def handle_event("configure_zrok", _, socket) do
    {:noreply, put_flash(socket, :error, "Please enter a URL")}
  end

  def handle_event("enable_environment", %{"account_token" => token}, socket) when token != "" do
    Zrok.enable_env(token)
    {:noreply, assign(socket, env_loading: true)}
  end

  def handle_event("enable_environment", _, socket) do
    {:noreply, put_flash(socket, :error, "Please enter an account token")}
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

  def handle_info(%{id: "sidebar_details", data: %{networks: networks, info: info}}, socket) do
    socket =
      socket
      |> assign(:networks, networks)
      |> assign(:wifi_info, info)
      |> assign(:scanning, false)

    {:noreply, socket}
  end

  def handle_info(%{type: :internet, status: status}, socket) do
    {:noreply, assign(socket, internet: status, connecting: false)}
  end

  def handle_info(%{type: type, message: message}, socket) when type in [:info, :error] do
    zrok_success = socket.assigns.zrok_loading and type == :info
    env_success = socket.assigns.env_loading and type == :info
    mesh_success = socket.assigns.mesh_loading and type == :info
    socket = put_flash(socket, type, message)

    {:noreply,
     assign(socket,
       connecting: false,
       zrok_loading: false,
       env_loading: false,
       mesh_loading: false,
       zrok_configured: socket.assigns.zrok_configured || zrok_success,
       env_enabled: socket.assigns.env_enabled || env_success,
       mesh_configured: socket.assigns.mesh_configured || mesh_success
     )}
  end

  def handle_info(:check_connection, socket) do
    internet = check_internet()
    start_scan()
    {:noreply, assign(socket, internet: internet, connecting: false, scanning: true)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp start_scan do
    Task.start(fn -> Wlan.scan_networks() end)
  end

  defp check_internet do
    try do
      Wlan.connected?()
    rescue
      _ -> false
    end
  end

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

  defp step_description(:wifi), do: "Connect to a Wi-Fi network for internet access"
  defp step_description(:zrok), do: "Configure your overlay network (optional)"
  defp step_description(:mesh), do: "Configure mesh relay (optional)"

  defp step_dot(step, current) do
    base = "w-3 h-3 rounded-full transition"

    cond do
      step == current -> "#{base} bg-accent"
      step_index(step) < step_index(current) -> "#{base} bg-green"
      true -> "#{base} bg-text-tertiary"
    end
  end

  defp step_index(:wifi), do: 0
  defp step_index(:zrok), do: 1
  defp step_index(:mesh), do: 2

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

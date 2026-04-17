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
    # If already onboarded, skip straight to dashboard
    if onboarded?() do
      {:ok, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "notifications")
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "status:internet")
      end

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

      # Kick off initial scan
      if connected?(socket), do: start_scan()

      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen bg-primary text-white">
      <div class="flex-1 flex flex-col items-center justify-center p-6">
        <div class="w-full max-w-lg">
          <!-- Header -->
          <div class="text-center mb-8">
            <h1 class="text-3xl font-bold mb-2">Setup Tunneld</h1>
            <p class="text-gray-1 text-sm">
              <%= step_description(@step) %>
            </p>
          </div>

          <!-- Progress -->
          <div class="flex items-center justify-center gap-3 mb-8">
            <div class={step_dot(:wifi, @step)} />
            <div class="w-8 h-px bg-gray-600" />
            <div class={step_dot(:zrok, @step)} />
          </div>

          <!-- Step content -->
          <%= render_step(assigns) %>
        </div>
      </div>
    </div>
    """
  end

  # Wi-Fi step
  defp render_step(%{step: :wifi} = assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Connection status -->
      <div class={"flex items-center gap-3 p-4 rounded-lg #{if @internet, do: "bg-green bg-opacity-10 border border-green border-opacity-30", else: "bg-secondary"}"}>
        <div class={"w-3 h-3 rounded-full #{if @internet, do: "bg-green", else: "bg-gray-500"}"} />
        <div>
          <div class="text-sm font-medium">
            <%= if @internet, do: "Connected to internet", else: "Not connected" %>
          </div>
          <div :if={@wifi_info["ssid"]} class="text-xs text-gray-1">
            Network: <%= @wifi_info["ssid"] %>
          </div>
        </div>
      </div>

      <!-- Scan button (hidden while scanning with no results — standalone loader shown instead) -->
      <button
        :if={!(@scanning and Enum.empty?(@networks))}
        phx-click="scan"
        disabled={@scanning}
        class={"flex items-center justify-center gap-2 w-full p-3 rounded-lg transition #{if @scanning, do: "bg-secondary text-gray-1 cursor-wait", else: "bg-secondary hover:bg-gray-700 cursor-pointer"}"}
      >
        <svg :if={@scanning} class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
        <.icon :if={!@scanning} class="w-4 h-4" name="hero-arrow-path" />
        <span class="text-sm"><%= if @scanning, do: "Scanning...", else: "Scan for networks" %></span>
      </button>

      <!-- Network list loading -->
      <div :if={@scanning and Enum.empty?(@networks)} class="flex flex-col items-center justify-center py-8 gap-2">
        <svg class="animate-spin h-6 w-6 text-gray-1" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
        <span class="text-xs text-gray-1">Scanning for networks...</span>
      </div>

      <div :if={!Enum.empty?(@networks)} class="space-y-2 max-h-64 overflow-y-auto system-scroll">
        <%= for network <- @networks do %>
          <% is_connected = @wifi_info["ssid"] == network.ssid %>
          <div
            class={"flex items-center justify-between p-3 rounded-lg cursor-pointer transition #{if is_connected, do: "bg-purple", else: "bg-secondary hover:bg-gray-700"}"}
            phx-click={unless is_connected, do: "select_network"}
            phx-value-ssid={network.ssid}
            phx-value-open={to_string(network.open)}
          >
            <div class="flex items-center gap-3 min-w-0">
              <.icon class="w-4 h-4 flex-shrink-0" name={if network.open, do: "hero-lock-open", else: "hero-lock-closed"} />
              <div class="truncate">
                <div class="text-sm truncate"><%= network.ssid %></div>
                <div class="text-xs text-gray-1"><%= network.signal %> dBm</div>
              </div>
            </div>
            <div :if={is_connected} class="text-xs bg-white bg-opacity-20 px-2 py-1 rounded">Connected</div>
          </div>
        <% end %>
      </div>

      <!-- Password modal (inline) -->
      <div :if={assigns[:selected_network]} class="bg-secondary rounded-lg p-4 space-y-3">
        <div class="text-sm font-medium">Connect to "<%= @selected_network %>"</div>
        <form phx-submit="connect_wifi" class="space-y-3">
          <input type="hidden" name="ssid" value={@selected_network} />
          <input
            :if={!assigns[:selected_open]}
            type="password"
            name="password"
            placeholder="Password"
            autocomplete="off"
            class="w-full bg-primary border border-gray-600 rounded-lg p-3 text-sm text-white placeholder-gray-500 focus:border-purple focus:outline-none"
          />
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="cancel_select"
              class="flex-1 p-3 rounded-lg bg-primary text-sm hover:bg-gray-700 transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={@connecting}
              class={"flex-1 p-3 rounded-lg text-sm transition flex items-center justify-center gap-2 #{if @connecting, do: "bg-purple bg-opacity-50 cursor-wait", else: "bg-purple hover:bg-opacity-80"}"}
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

      <!-- Next / Skip -->
      <div class="flex gap-3 pt-4">
        <button
          phx-click="next_step"
          class={"flex-1 p-3 rounded-lg text-sm font-medium transition #{if @internet, do: "bg-purple hover:bg-opacity-80", else: "bg-secondary hover:bg-gray-700 text-gray-1"}"}
        >
          <%= if @internet, do: "Next", else: "Skip (no internet)" %>
        </button>
      </div>
    </div>
    """
  end

  # Zrok step
  defp render_step(%{step: :zrok} = assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- All done: control plane + device enabled -->
      <div :if={@zrok_configured and @env_enabled} class="flex flex-col items-center justify-center py-6 gap-3">
        <div class="w-12 h-12 rounded-full bg-green bg-opacity-10 flex items-center justify-center">
          <.icon name="hero-check" class="w-6 h-6 text-green" />
        </div>
        <div class="text-center">
          <div class="text-sm font-medium">Device enabled on overlay network</div>
          <div class="text-xs text-gray-1 mt-1">You can manage this from the dashboard</div>
        </div>
      </div>

      <div :if={@zrok_configured and @env_enabled} class="flex gap-3 pt-4">
        <button
          phx-click="finish_setup"
          class="w-full p-3 rounded-lg bg-purple text-sm font-medium hover:bg-opacity-80 transition"
        >
          Finish
        </button>
      </div>

      <!-- Control plane set — now enable device -->
      <div :if={@zrok_configured and not @env_enabled} class="flex items-center gap-3 p-4 rounded-lg bg-green bg-opacity-10 border border-green border-opacity-30">
        <div class="w-3 h-3 rounded-full bg-green" />
        <div class="text-sm font-medium">Control plane configured</div>
      </div>

      <form :if={@zrok_configured and not @env_enabled} phx-submit="enable_environment" class="space-y-3">
        <div>
          <label class="text-xs text-gray-1 mb-1 block">Account Token</label>
          <input
            type="password"
            name="account_token"
            placeholder="Account token from your control plane"
            autocomplete="off"
            class="w-full bg-secondary border border-gray-600 rounded-lg p-3 text-sm text-white placeholder-gray-500 focus:border-purple focus:outline-none"
          />
        </div>
        <button
          type="submit"
          disabled={@env_loading}
          class={"w-full p-3 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 #{if @env_loading, do: "bg-purple bg-opacity-50 cursor-wait", else: "bg-purple hover:bg-opacity-80"}"}
        >
          <svg :if={@env_loading} class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <%= if @env_loading, do: "Enabling device...", else: "Enable Device" %>
        </button>
      </form>

      <div :if={@zrok_configured and not @env_enabled} class="flex gap-3 pt-4">
        <button
          phx-click="prev_step"
          class="flex-1 p-3 rounded-lg bg-secondary text-sm hover:bg-gray-700 transition"
        >
          Back
        </button>
        <button
          phx-click="finish_setup"
          class="flex-1 p-3 rounded-lg bg-purple text-sm font-medium hover:bg-opacity-80 transition"
        >
          Finish
        </button>
      </div>

      <!-- Initial: configure control plane URL -->
      <div :if={not @zrok_configured} class="bg-secondary rounded-lg p-4">
        <div class="text-sm">
          Zrok enables secure tunnels to expose your local services to the internet
          without port forwarding. This step is optional — you can configure it later
          from the dashboard.
        </div>
      </div>

      <form :if={not @zrok_configured} phx-submit="configure_zrok" class="space-y-3">
        <div>
          <label class="text-xs text-gray-1 mb-1 block">Control Plane URL</label>
          <input
            type="url"
            name="url"
            placeholder="https://zrok.example.com"
            class="w-full bg-secondary border border-gray-600 rounded-lg p-3 text-sm text-white placeholder-gray-500 focus:border-purple focus:outline-none"
          />
        </div>
        <button
          type="submit"
          disabled={@zrok_loading}
          class={"w-full p-3 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 #{if @zrok_loading, do: "bg-purple bg-opacity-50 cursor-wait", else: "bg-purple hover:bg-opacity-80"}"}
        >
          <svg :if={@zrok_loading} class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <%= if @zrok_loading, do: "Configuring...", else: "Configure Control Plane" %>
        </button>
      </form>

      <div :if={not @zrok_configured} class="flex gap-3 pt-4">
        <button
          phx-click="prev_step"
          class="flex-1 p-3 rounded-lg bg-secondary text-sm hover:bg-gray-700 transition"
        >
          Back
        </button>
        <button
          phx-click="finish_setup"
          class="flex-1 p-3 rounded-lg bg-purple text-sm font-medium hover:bg-opacity-80 transition"
        >
          Skip & Finish
        </button>
      </div>
    </div>
    """
  end

  # -- Events --

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

    # Check connection after a delay
    Process.send_after(self(), :check_connection, 5000)
    {:noreply, socket}
  end

  def handle_event("next_step", _, socket) do
    next =
      case socket.assigns.step do
        :wifi -> :zrok
        :zrok -> :zrok
      end

    {:noreply, assign(socket, :step, next)}
  end

  def handle_event("prev_step", _, socket) do
    prev =
      case socket.assigns.step do
        :wifi -> :wifi
        :zrok -> :wifi
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

  def handle_event("finish_setup", _, socket) do
    mark_onboarded()
    {:noreply, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
  end

  # -- PubSub handlers --

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
    socket = put_flash(socket, type, message)

    {:noreply,
     assign(socket,
       connecting: false,
       zrok_loading: false,
       env_loading: false,
       zrok_configured: socket.assigns.zrok_configured || zrok_success,
       env_enabled: socket.assigns.env_enabled || env_success
     )}
  end

  def handle_info(:check_connection, socket) do
    internet = check_internet()
    start_scan()
    {:noreply, assign(socket, internet: internet, connecting: false, scanning: true)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # -- Helpers --

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

  defp step_dot(step, current) do
    base = "w-3 h-3 rounded-full transition"

    cond do
      step == current -> "#{base} bg-purple"
      step_index(step) < step_index(current) -> "#{base} bg-green"
      true -> "#{base} bg-gray-600"
    end
  end

  defp step_index(:wifi), do: 0
  defp step_index(:zrok), do: 1
end

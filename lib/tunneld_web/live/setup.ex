defmodule TunneldWeb.Live.Setup do
  @moduledoc """
  First-run setup wizard shown after initial account creation.

  Tracked via an `onboarded` flag in auth.json so it only appears once.
  Currently a single confirmation step; future machine enrollment will
  live in the dashboard, not here.
  """

  use TunneldWeb, :live_view
  require Logger

  alias Tunneld.Servers.Auth
  alias TunneldWeb.Router.Helpers, as: Routes

  on_mount TunneldWeb.Hooks.CheckAuth

  @capabilities [
    %{
      icon: "hero-globe-alt",
      title: "Edge gateway",
      body:
        "Turns this device into a wired gateway: DHCP + DNS for everything on the downstream LAN port, with NAT and forwarding handled automatically."
    },
    %{
      icon: "hero-server-stack",
      title: "Machine discovery",
      body:
        "Enroll machines (on the subnet or over the internet) and discover what is listening on them with ss -tlnp — runtime-agnostic (Incus, Docker, systemd, or a bare binary)."
    },
    %{
      icon: "hero-link",
      title: "Expose services",
      body:
        "Promote any listener to a named resource on the LAN at <name>.tunneld.lan — and reach remote machines over a WireGuard overlay as if they were local."
    },
    %{
      icon: "hero-cpu-chip",
      title: "Health & monitoring",
      body:
        "Track link state, resources, system load, and manage which DNS resolver your subnet uses."
    }
  ]

  @doc "Which capabilities this build actually offers (no Wi-Fi, no zrok, no mesh)."
  def capabilities, do: @capabilities

  @impl true
  def mount(_params, %{"client_id" => client_id} = _session, socket) do
    if onboarded?() do
      {:ok, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "notifications")
      end

      {:ok, assign(socket, step: :welcome, client_id: client_id, capabilities: @capabilities)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen bg-bg text-text-primary">
      <div class="flex-1 flex flex-col items-center justify-center p-6">
        <div class="w-full max-w-xl">
          <div class="text-center mb-8">
            <h1 class="text-3xl font-semibold mb-2 -tracking-[0.01em]">Setup Tunneld</h1>
            <p class="text-text-secondary text-sm"><%= step_description(@step) %></p>
          </div>

          <%= render_step(assigns) %>
        </div>
      </div>
    </div>
    """
  end

  defp render_step(%{step: :requirements} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="bg-surface rounded-lg p-4 text-sm text-text-secondary">
        To connect remote machines over the WireGuard overlay and expose services
        publicly, two network prerequisites must be met on each target:
      </div>
      <div class="bg-surface border border-border rounded-lg p-4">
        <ul class="text-sm text-text-secondary space-y-3">
          <li>
            <span class="font-medium text-text-primary">WireGuard port (default 51820/UDP)</span>
            <div class="text-xs text-text-tertiary mt-0.5">
              Must be allowed <b>inbound</b>
              in the target's <b>provider firewall</b>
              (e.g. a Vultr security
              group). This is separate from the OS firewall and cannot be changed over SSH.
            </div>
          </li>
          <li>
            <span class="font-medium text-text-primary">Exposed TCP port (for public exposure)</span>
            <div class="text-xs text-text-tertiary mt-0.5">
              Open the service port inbound in the provider firewall for internet reachability.
            </div>
          </li>
          <li>
            <span class="font-medium text-text-primary">SSH key</span>
            <div class="text-xs text-text-tertiary mt-0.5">
              After enrollment, install tunneld's public key into the target's ~/.ssh/authorized_keys.
            </div>
          </li>
        </ul>
      </div>
      <button
        phx-click="finish_setup"
        class="w-full bg-accent hover:bg-accent-light p-2 rounded-md text-white text-sm"
      >
        Got it — go to dashboard
      </button>
    </div>
    """
  end

  defp render_step(%{step: :welcome} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="bg-surface rounded-lg p-4">
        <div class="text-sm text-text-secondary">
          Your gateway is running and your subnet is ready. Here's what it can do.
        </div>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <%= for cap <- @capabilities do %>
          <div class="bg-surface border border-border rounded-lg p-4">
            <div class="flex items-center gap-2 mb-1">
              <.icon name={cap.icon} class="w-4 h-4 text-accent" />
              <div class="text-sm font-medium"><%= cap.title %></div>
            </div>
            <div class="text-xs text-text-secondary leading-relaxed"><%= cap.body %></div>
          </div>
        <% end %>
      </div>

      <div class="flex flex-col gap-2 pt-4">
        <button
          phx-click="next_step"
          class="w-full p-3 rounded-lg bg-accent text-sm font-medium hover:bg-accent-light transition"
        >
          Next: connection requirements →
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("next_step", _, socket) do
    {:noreply, assign(socket, step: :requirements)}
  end

  @impl true
  def handle_event("finish_setup", _, socket) do
    mark_onboarded()
    {:noreply, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
  end

  @impl true
  def handle_info(%{type: type, message: message}, socket) when type in [:info, :error] do
    {:noreply, put_flash(socket, type, message)}
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

  defp step_description(:welcome), do: "Welcome"
  defp step_description(:requirements), do: "Before you connect machines"
end

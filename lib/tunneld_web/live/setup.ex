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

  def mount(_params, %{"client_id" => _client_id} = _session, socket) do
    if onboarded?() do
      {:ok, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
        Phoenix.PubSub.subscribe(Tunneld.PubSub, "notifications")
      end

      {:ok, assign(socket, step: :welcome)}
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
            <div class={step_dot(:welcome, @step)} />
          </div>

          <%= render_step(assigns) %>
        </div>
      </div>
    </div>
    """
  end

  defp render_step(%{step: :welcome} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="bg-surface rounded-lg p-4">
        <div class="text-sm text-text-secondary">
          Your gateway is ready. You can add managed machines and provision
          containers from the dashboard at any time.
        </div>
      </div>

      <div class="flex gap-3 pt-4">
        <button phx-click="finish_setup" class="w-full p-3 rounded-lg bg-accent text-sm font-medium hover:bg-accent-light transition">
          Finish
        </button>
      </div>
    </div>
    """
  end

  def handle_event("finish_setup", _, socket) do
    mark_onboarded()
    {:noreply, push_navigate(socket, to: Routes.live_path(socket, TunneldWeb.Live.Dashboard))}
  end

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

  defp step_dot(step, current) do
    base = "w-3 h-3 rounded-full transition"

    cond do
      step == current -> "#{base} bg-accent"
      step_index(step) < step_index(current) -> "#{base} bg-green"
      true -> "#{base} bg-text-tertiary"
    end
  end

  defp step_index(:welcome), do: 0
end
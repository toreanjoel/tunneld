defmodule TunneldWeb.Live.Components.Welcome do
  @moduledoc """
  The welcome message to welcome the user. This will contain message and some details potentially.
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:welcome")
    end
    {:ok, socket}
  end

  def update(assigns, socket) do
    data = Map.get(assigns, :data) || Tunneld.Servers.Updater.get_status()
    ai_configured = Tunneld.Servers.Ai.configured?()
    {:ok, socket |> assign(data: data) |> assign(:ai_configured, ai_configured)}
  end

  @doc """
  Show the message and subtext that could be used as subtext information (Disabled AI Overview)
  """
  def render(assigns) do
    assigns = assigns |> assign(version: Map.get(assigns.data, :version, Application.get_env(:tunneld, :version)))
    ~H"""
    <div class="py-5">
      <div class="text-4xl font-medium bg-gradient-to-r from-slate-300 to-slate-600 bg-clip-text text-transparent">
        Tunneld
      </div>
      <div class="text-xs text-gray-500"><%= Application.get_env(:tunneld, :metadata)[:device_id] || System.get_env("DEVICE_ID") %></div>
      <div class="flex flex-row items-center gap-2">
        <div class="text-lg text-gray-2 font-light">
          <%= @version %>
        </div>
        <div :if={Map.get(@data, :is_latest, true) and not is_nil(Map.get(@data, :new_version))} class="bg-blue-800 bg-opacity-20 py-1 px-2 rounded-md text-xs text-blue-500">
          <%= "Update Available: " <> Map.get(@data, :new_version) %>
        </div>
        <div
          :if={not @ai_configured}
          phx-click="show_details"
          phx-value-type="ai_settings"
          phx-value-id="_"
          class="bg-purple bg-opacity-20 py-1 px-2 rounded-md text-xs text-purple cursor-pointer hover:opacity-80 transition-all"
        >
          Connect AI Assistant
        </div>
      </div>
    </div>
    """
  end
end

defmodule TunneldWeb.Live.Components.Wireguard.Server do
  @moduledoc """
  WireGuard VPN server toggle and status display.

  Shows the on/off toggle, public key, listen port, and endpoint.
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:wireguard")
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(enabled: assigns.data["enabled"] || false)
      |> assign(public_key: assigns.data["public_key"])
      |> assign(listen_port: assigns.data["listen_port"])
      |> assign(endpoint: assigns.data["endpoint"])
      |> assign(subnet: assigns.data["subnet"])

    ~H"""
    <div class="p-3 md:p-5">
      <div class="mb-4 md:mb-5 flex flex-row items-center gap-2">
        <div class="flex-1">
          <div class="text-lg md:text-xl text-gray-1 font-medium">VPN Server</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div class="flex flex-row gap-1">
          <div
            phx-click="toggle_vpn"
            phx-value-enabled={(!@enabled) |> to_string()}
            phx-click-loading="opacity-50 cursor-wait"
            class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
          >
            <.icon class="w-5 h-5 sm:w-6 sm:h-6" name={if @enabled, do: "hero-lock-open", else: "hero-lock-closed"} />
            <div class="hidden sm:block truncate text-xs">
              <%= if @enabled, do: "Disable", else: "Enable" %>
            </div>
          </div>
        </div>
      </div>

      <div :if={@enabled} class="space-y-2 text-xs text-gray-300">
        <div class="flex items-center justify-between">
          <span class="text-gray-400">Public Key</span>
          <span class="font-mono text-[10px] break-all max-w-[200px]" title={@public_key}>
            <%= if @public_key, do: String.slice(@public_key, 0, 20) <> "...", else: "—" %>
          </span>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-gray-400">Listen Port</span>
          <span><%= @listen_port || "—" %></span>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-gray-400">Endpoint</span>
          <span><%= @endpoint || "—" %></span>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-gray-400">Subnet</span>
          <span><%= @subnet || "—" %></span>
        </div>
      </div>

      <div :if={!@enabled} class="mt-2 text-xs text-gray-400">
        VPN server is disabled. Enable to create peer connections.
      </div>
    </div>
    """
  end
end
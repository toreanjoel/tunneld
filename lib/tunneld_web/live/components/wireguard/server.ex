defmodule TunneldWeb.Live.Components.Wireguard.Server do
  @moduledoc """
  WireGuard VPN server summary section on the dashboard.

  Uses the same header style as Resources/Devices sections.
  Shows detail rows in the sidebar summary pattern (label + value).
  Action button on the top right opens the sidebar with full configuration.
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    obfuscated = Map.get(assigns, :obfuscated, false)

    socket =
      socket
      |> assign_new(:obfuscated, fn -> false end)
      |> assign(data: Map.get(assigns, :data, %{}))
      |> assign(:obfuscated, obfuscated)

    {:ok, socket}
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(enabled: assigns.data["enabled"] || false)
      |> assign(endpoint: assigns.data["endpoint"])
      |> assign(peers: assigns.data["peers"] || %{})
      |> assign(public_key: assigns.data["public_key"])
      |> assign(listen_port: assigns.data["listen_port"])
      |> assign(subnet: assigns.data["subnet"])

    ~H"""
    <div class="p-3 md:p-5">
      <div class="mb-4 md:mb-5 flex flex-row">
        <div class="flex-1">
          <div class="text-lg md:text-xl text-gray-1 font-medium">VPN</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div>
          <div
            phx-click="show_details"
            phx-value-type="wireguard"
            phx-value-id="_"
            class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
          >
            <.icon class="w-5 h-5 sm:w-6 sm:h-6" name="hero-shield-check" />
            <div class="hidden sm:block truncate text-xs">Configure VPN</div>
          </div>
        </div>
      </div>

      <div class="bg-primary rounded-lg p-3">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2 text-xs">
          <div class="truncate">
            <span class="font-semibold">Status:</span>
            <span class={"ml-1 w-[13px] h-[13px] rounded-full inline-block align-middle #{if @enabled, do: "bg-green", else: "bg-red"}"}></span>
          </div>
          <div class="truncate">
            <span class="font-semibold">Endpoint:</span>
            <span class="ml-1"><%= mask(@obfuscated, @endpoint || "—") %></span>
          </div>
          <div class="truncate">
            <span class="font-semibold">Subnet:</span>
            <span class="ml-1"><%= mask(@obfuscated, @subnet || "—") %></span>
          </div>
          <div class="truncate">
            <span class="font-semibold">Listen Port:</span>
            <span class="ml-1"><%= mask(@obfuscated, @listen_port || "—") %></span>
          </div>
          <div class="truncate">
            <span class="font-semibold">Public Key:</span>
            <span class="ml-1 font-mono text-[10px]"><%= mask(@obfuscated, (if @public_key, do: String.slice(@public_key, 0, 16) <> "...", else: "—")) %></span>
          </div>
          <div class="truncate">
            <span class="font-semibold">Peers:</span>
            <span class="ml-1"><%= map_size(@peers) %></span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
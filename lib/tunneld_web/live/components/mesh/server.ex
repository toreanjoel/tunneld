defmodule TunneldWeb.Live.Components.Mesh.Server do
  @moduledoc """
  Mesh status card replacing the old VPN card.
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
    data = assigns.data || %{}
    status = Map.get(data, :status, :disabled)
    enabled = status != :disabled

    peers = Map.get(data, :peers, %{})
    relay_endpoint = Map.get(data, :relay_endpoint)
    relay_pubkey = Map.get(data, :relay_pubkey)
    mesh_ip = Map.get(data, :mesh_ip)
    token = Map.get(data, :token)
    last_sync = Map.get(data, :last_sync)

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:enabled, enabled)
      |> assign(:peers, peers)
      |> assign(:relay_endpoint, relay_endpoint)
      |> assign(:relay_pubkey, relay_pubkey)
      |> assign(:mesh_ip, mesh_ip)
      |> assign(:token, token)
      |> assign(:last_sync, last_sync)
      |> assign(:status_text, status_text(status))
      |> assign(:status_color, status_color(status))

    ~H"""
    <div class="p-3 md:p-5">
      <div class="mb-4 md:mb-5 flex flex-row items-center gap-2">
        <div class="flex-1">
          <div class="text-lg md:text-xl text-gray-1 font-medium">Mesh</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div class="flex flex-row gap-2">
          <div
            phx-click="show_details"
            phx-value-type="mesh"
            phx-value-id="_"
            class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
          >
            <.icon class="w-5 h-5 sm:w-6 sm:h-6" name="hero-globe-alt" />
            <div class="hidden sm:block truncate text-xs">Configure Mesh</div>
          </div>
        </div>
      </div>

      <div class="bg-primary rounded-lg p-3 space-y-3">
        <%= if @enabled do %>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2 text-xs">
            <div class="truncate">
              <span class="font-semibold">Status:</span>
              <span class={"ml-1 w-[13px] h-[13px] rounded-full inline-block align-middle #{@status_color}"}></span>
              <span class="ml-1"><%= @status_text %></span>
            </div>
            <div class="truncate">
              <span class="font-semibold">Mesh IP:</span>
              <span class="ml-1"><%= mask(@obfuscated, @mesh_ip || "—") %></span>
            </div>
            <div class="truncate">
              <span class="font-semibold">Relay Endpoint:</span>
              <span class="ml-1 font-mono text-[10px]"><%= mask(@obfuscated, @relay_endpoint || "—") %></span>
              <span
                :if={@relay_endpoint}
                phx-click="copy_to_clipboard"
                phx-value-text={@relay_endpoint}
                class="ml-1 cursor-pointer text-blue-400 hover:text-blue-300"
                title="Copy"
              >
                <.icon class="w-3 h-3" name="hero-clipboard" />
              </span>
            </div>
            <div class="truncate">
              <span class="font-semibold">Relay Pubkey:</span>
              <span class="ml-1 font-mono text-[10px]"><%= mask(@obfuscated, (if @relay_pubkey, do: String.slice(@relay_pubkey, 0, 16) <> "...", else: "—")) %></span>
              <span
                :if={@relay_pubkey}
                phx-click="copy_to_clipboard"
                phx-value-text={@relay_pubkey}
                class="ml-1 cursor-pointer text-blue-400 hover:text-blue-300"
                title="Copy"
              >
                <.icon class="w-3 h-3" name="hero-clipboard" />
              </span>
            </div>
            <div class="truncate">
              <span class="font-semibold">Token:</span>
              <span class="ml-1"><%= mask(@obfuscated, (if @token, do: String.slice(to_string(@token), 0, 4) <> "••••", else: "—")) %></span>
            </div>
            <div class="truncate">
              <span class="font-semibold">Last Sync:</span>
              <span class="ml-1"><%= if @last_sync, do: Calendar.strftime(@last_sync, "%H:%M:%S"), else: "—" %></span>
            </div>
          </div>

          <div>
            <div class="flex items-center justify-between mb-2">
              <span class="text-sm font-semibold">Connected Nodes (<%= map_size(@peers) %>)</span>
              <div class="flex gap-2">
                <button
                  phx-click="trigger_action"
                  phx-value-action="mesh_sync"
                  phx-value-data="{}"
                  class="text-xs text-blue-400 hover:text-blue-300 cursor-pointer"
                >
                  Sync Now
                </button>
                <button
                  phx-click="trigger_action"
                  phx-value-action="disconnect_mesh"
                  phx-value-data="{}"
                  class="text-xs text-red-400 hover:text-red-300 cursor-pointer"
                >
                  Disconnect
                </button>
              </div>
            </div>

            <div :if={Enum.empty?(@peers)} class="text-xs text-gray-400 text-center py-2">
              No connected nodes
            </div>

            <div :if={!Enum.empty?(@peers)} class="space-y-1 max-h-32 overflow-y-auto system-scroll">
              <%= for {_pubkey, peer} <- @peers do %>
                <div class="flex items-center justify-between bg-secondary rounded p-2 text-xs">
                  <div>
                    <div class="font-medium text-gray-1"><%= peer["name"] %></div>
                    <div class="text-[10px] text-gray-400 font-mono"><%= peer["mesh_ip"] %></div>
                  </div>
                  <div class="text-[10px] text-gray-400 text-right">
                    <div><%= Enum.join(peer["allowed_ips"] || [], ", ") %></div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="text-sm text-gray-1">
            Mesh networking connects this node to other tunneld instances through a relay.
            No port forwarding required, all devices connect through the relay's public IP.
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_text(:disabled), do: "Disabled"
  defp status_text(:connecting), do: "Connecting"
  defp status_text(:connected), do: "Connected"
  defp status_text(:relay_unreachable), do: "Relay Unreachable"
  defp status_text(_), do: "Unknown"

  defp status_color(:disabled), do: "bg-gray-500"
  defp status_color(:connecting), do: "bg-yellow-500"
  defp status_color(:connected), do: "bg-green"
  defp status_color(:relay_unreachable), do: "bg-red"
  defp status_color(_), do: "bg-gray-500"
end

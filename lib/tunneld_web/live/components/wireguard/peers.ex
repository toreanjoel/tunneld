defmodule TunneldWeb.Live.Components.Wireguard.Peers do
  @moduledoc """
  WireGuard peer list with create and revoke actions.
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
      |> assign(peers: assigns.data["peers"] || %{})

    ~H"""
    <div class="p-3 md:p-5">
      <div class="mb-4 md:mb-5 flex flex-row items-center gap-2">
        <div class="flex-1">
          <div class="text-lg md:text-xl text-gray-1 font-medium">VPN Peers</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div :if={@enabled} class="flex flex-row gap-1">
          <div
            phx-click="modal_open"
            phx-value-modal_title="Add VPN Peer"
            phx-value-modal_body={
              Jason.encode!(%{
                "type" => "schema",
                "data" => Tunneld.Schema.Wireguard.data(:add_peer),
                "default_values" => %{
                  "name" => "",
                  "full_tunnel" => false
                },
                "action" => "add_wireguard_peer"
              })
            }
            phx-click-loading="opacity-50 cursor-wait"
            class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
          >
            <.icon class="w-5 h-5 sm:w-6 sm:h-6" name="hero-plus" />
            <div class="hidden sm:block truncate text-xs">Add Peer</div>
          </div>
        </div>
      </div>

      <div>
        <div
          :if={!@enabled or Enum.empty?(@peers)}
          class="w-[60px] h-[60px] bg-secondary flex items-center justify-center rounded-md opacity-10"
        >
          <.icon class="w-8 h-8 text-white" name="hero-device-phone-mobile" />
        </div>

        <div :if={@enabled and !Enum.empty?(@peers)} class="space-y-2">
          <%= for {_id, peer} <- @peers do %>
            <div class="flex items-center justify-between p-3 rounded-lg bg-secondary">
              <div class="flex items-center gap-3">
                <.icon class="w-5 h-5 shrink-0" name="hero-device-phone-mobile" />
                <div>
                  <div class="text-xs font-semibold text-gray-1"><%= peer["name"] %></div>
                  <div class="text-[10px] text-gray-400 font-mono"><%= peer["ip"] %></div>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span class={
                  "px-2 py-0.5 rounded-full text-[10px] font-medium " <>
                  if peer["full_tunnel"], do: "bg-green-500/20 text-green-400", else: "bg-blue-500/20 text-blue-400"
                }>
                  <%= if peer["full_tunnel"], do: "Full Tunnel", else: "Split Tunnel" %>
                </span>
                <div
                  phx-click="revoke_wireguard_peer"
                  phx-value-peer_id={peer["id"]}
                  phx-value-peer_name={peer["name"]}
                  class="p-1 rounded hover:bg-red-500/20 cursor-pointer transition-colors duration-150"
                  title="Revoke peer"
                >
                  <.icon class="w-4 h-4 text-red-400" name="hero-trash" />
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
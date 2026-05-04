defmodule TunneldWeb.Live.Components.Mesh.Nodes do
  @moduledoc """
  Mesh peer nodes rendered as a card grid.
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
    peers = Map.get(data, :peers, %{})

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:peers, peers)

    ~H"""
    <div class="p-3 md:p-5">
      <div :if={@status == :connected} class="min-h-[150px] md:min-h-[200px]">
        <div class="mb-4 md:mb-5 flex flex-row items-center gap-2">
          <div class="flex-1">
            <div class="text-lg md:text-xl text-gray-1 font-medium">Mesh Nodes</div>
            <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
          </div>
          <div class="flex flex-row items-center gap-2">
            <div
              phx-click="trigger_action"
              phx-value-action="mesh_sync"
              phx-value-data="{}"
              class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
            >
              <.icon class="w-4 h-4" name="hero-arrow-path" />
              <div class="hidden sm:block truncate text-xs">Sync Now</div>
            </div>
            <div
              phx-click="trigger_action"
              phx-value-action="disconnect_mesh"
              phx-value-data="{}"
              class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
            >
              <.icon class="w-4 h-4" name="hero-x-mark" />
              <div class="hidden sm:block truncate text-xs">Disconnect</div>
            </div>
          </div>
        </div>

        <div :if={Enum.empty?(@peers)} class="text-xs text-gray-400 text-center py-4">
          No connected nodes
        </div>

        <div :if={not Enum.empty?(@peers)} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
          <%= for {_pubkey, peer} <- @peers do %>
            <div
              class="p-4 flex flex-col bg-secondary rounded-lg w-full min-h-[130px] h-auto hover:bg-secondary"
              style="animation: fadeIn 0.5s ease-out forwards;"
            >
              <div class="flex flex-row gap-2 items-center">
                <div class="flex-1 truncate text-sm font-medium"><%= peer["name"] %></div>
              </div>
              <div class="grow"></div>
              <div class="mt-auto space-y-1">
                <div class="text-xs text-gray-400 font-mono"><%= mask(@obfuscated, peer["mesh_ip"] || "—") %></div>
                <div :if={peer["allowed_ips"] != []} class="text-[10px] text-gray-500 truncate">
                  <%= Enum.join(peer["allowed_ips"], ", ") %>
                </div>
                <div :if={peer["last_seen"]} class="text-[10px] text-gray-500">
                  Last seen: <%= Calendar.strftime(DateTime.from_unix!(peer["last_seen"], :millisecond), "%H:%M:%S") %>
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

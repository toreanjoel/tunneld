defmodule TunneldWeb.Live.Components.MeshCard do
  @moduledoc """
  Mesh network hero card with globe visualization, connection status, peer count,
  mesh IP, last sync time, and configure button.
  """
  use Phoenix.Component
  import TunneldWeb.Icons

  attr :connected, :boolean, default: false
  attr :peer_count, :integer, default: 0
  attr :mesh_ip, :string, default: nil
  attr :last_sync, :string, default: nil
  attr :relay, :string, default: nil

  def mesh_card(assigns) do
    ~H"""
    <div class="hero-card flex flex-col">
      <div class="px-7 pt-6 pb-4 flex justify-between items-start relative z-[2]">
        <div class="text-[11px] tracking-[0.08em] uppercase text-accent font-medium">
          MESH NETWORK
        </div>
        <div :if={@connected} class="font-mono text-[11px] text-text-primary/75 leading-[1.7] text-right">
          <div><span class="text-text-tertiary">peers </span><%= @peer_count %></div>
          <div><span class="text-text-tertiary">mesh ip </span><%= @mesh_ip %></div>
          <div><span class="text-text-tertiary">sync </span><%= @last_sync %></div>
        </div>
      </div>

      <div class="relative flex-1 flex items-center justify-center min-h-[200px]">
        <div :if={!@connected} class="text-[13px] text-text-secondary italic">Connect to a relay to enable mesh</div>
      </div>

      <div class="h-px bg-border mx-6" />

      <div class="px-7 py-5 flex items-center justify-between gap-4 bg-surface">
        <div class="flex-1 min-w-0">
          <div class="text-[11px] tracking-[0.08em] uppercase text-text-secondary font-medium mb-2">
            MESH
          </div>
          <div class="text-2xl text-text-primary font-medium -tracking-[0.01em] leading-tight">
            <%= if @connected, do: "#{@peer_count} peers", else: "Disabled" %>
          </div>
          <div class={"text-[13px] text-text-secondary mt-1.5 overflow-hidden text-ellipsis whitespace-nowrap #{if @connected, do: "font-mono", else: ""}"}>
            <%= if @connected, do: @relay, else: "No relay configured" %>
          </div>
        </div>
        <div class="flex gap-1">
          <button :if={@connected} class="ghost-icon" phx-click="show_details" phx-value-type="mesh" phx-value-id="_" aria-label="Configure mesh">
            <.settings size={16} />
          </button>
          <button :if={!@connected} class="ghost-btn" phx-click="show_details" phx-value-type="mesh" phx-value-id="_">Configure</button>
        </div>
      </div>
    </div>
    """
  end
end

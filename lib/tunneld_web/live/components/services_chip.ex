defmodule TunneldWeb.Live.Components.ServicesChip do
  @moduledoc """
  Services chip that shows service count with a popover on click.
  Deprecated — functionality moved into TopBar component for proper positioning.
  """
  use Phoenix.Component
  import TunneldWeb.Icons

  attr :services, :list, default: []

  def services_popover(assigns) do
    ~H"""
    <div class="absolute top-full right-0 mt-1 min-w-[200px] bg-surface border border-border rounded-[10px] p-2 z-[61] shadow-[0_8px_24px_rgba(0,0,0,0.5)]">
      <%= for s <- @services do %>
        <% up = Map.get(s, :up, true) %>
        <div class="flex items-center gap-2.5 px-2.5 py-2 text-[13px] font-mono text-text-primary">
          <span class={"status-dot #{if up, do: "status-dot--green", else: "status-dot--red"}"} />
          <span class="flex-1"><%= s.name %></span>
          <span class="text-[11px] text-text-tertiary uppercase tracking-[0.08em]">
            <%= if up, do: "up", else: "down" %>
          </span>
        </div>
      <% end %>
    </div>
    """
  end
end

defmodule TunneldWeb.Live.Components.DnsCard do
  @moduledoc """
  DNS server status card showing the current resolver.
  Clicking opens the DNS configuration sidebar.
  """
  use Phoenix.Component
  import TunneldWeb.Icons

  attr :server, :string, default: "—"

  def dns_card(assigns) do
    ~H"""
    <div class="hero-card px-6 py-5 flex flex-col gap-3.5 cursor-pointer" phx-click="show_details" phx-value-type="dns_server" phx-value-id="_">
      <div class="flex justify-between items-center">
        <div class="text-[11px] tracking-[0.08em] uppercase text-text-secondary font-medium">
          DNS SERVER
        </div>
        <span class="text-text-tertiary inline-flex">
          <.chevron_right size={14} />
        </span>
      </div>
      <div class="flex flex-col items-center justify-center gap-1.5 flex-1">
        <div class="font-mono text-[22px] text-text-primary font-medium -tracking-[0.01em]">
          <%= @server %>
        </div>
      </div>
    </div>
    """
  end
end

defmodule TunneldWeb.Live.Components.TopBar do
  @moduledoc """
  Top navigation bar with services chip, configure button, obfuscation toggle,
  settings dropdown, and version info badge.
  """
  use Phoenix.Component
  use Gettext, backend: TunneldWeb.Gettext
  import TunneldWeb.Icons
  import TunneldWeb.Live.Components.SettingsDropdown

  alias Phoenix.LiveView.JS

  attr :services, :list, default: []
  attr :version, :string, default: nil
  attr :update_available, :boolean, default: false
  attr :new_version, :string, default: nil
  attr :obfuscated, :boolean, default: false
  attr :settings_menu_open, :boolean, default: false
  attr :services_popover_open, :boolean, default: false
  attr :device_id, :string, default: nil

  def top_bar(assigns) do
    ~H"""
    <div class="relative flex items-center justify-between h-[72px] px-8">
      <div :if={@services_popover_open} class="fixed inset-0 z-60" phx-click="toggle_services_popover" />
      <%= if @settings_menu_open do %>
        <div class="fixed inset-0 z-40" phx-click="close_settings_menu" />
      <% end %>
      <div class="flex items-center gap-2.5">
        <span class="text-lg font-medium text-text-primary -tracking-[0.01em]">Tunneld</span>
        <div :if={@version} class="hidden sm:flex items-center gap-2 ml-2">
          <span class="text-xs text-text-tertiary font-mono"><%= @version %></span>
          <span
            :if={@update_available and @new_version}
            class="bg-accent/15 text-accent px-2 py-0.5 rounded text-[10px] font-mono"
          >
            <%= @new_version %>
          </span>
        </div>
      </div>

      <div class="flex items-center gap-2 relative">
        <div class="relative">
          <button class="services-chip" phx-click="toggle_services_popover">
            <% up_count = Enum.count(@services, & Map.get(&1, :up, true)) %>
            <% total = length(@services) %>
            <% has_failing = Enum.any?(@services, fn s -> not Map.get(s, :up, true) end) %>
            <span class={"status-dot #{if has_failing, do: "status-dot--red", else: "status-dot--green"}"} />
            <span class="text-[11px] text-text-primary tracking-[0.06em] font-medium">
              Services <%= up_count %>/<%= total %>
            </span>
          </button>
          <div
            :if={@services_popover_open}
            class="absolute top-full right-0 mt-1 min-w-[200px] bg-surface border border-border rounded-[10px] p-2 z-[61] shadow-[0_8px_24px_rgba(0,0,0,0.5)]"
          >
            <%= for s <- @services do %>
              <% up = Map.get(s, :up, true) %>
              <div class="flex items-center gap-2.5 px-2.5 py-2 text-[13px] font-mono text-text-primary cursor-pointer menu-item" phx-click="show_details" phx-value-type="service" phx-value-id={to_string(s.name)}>
                <span class={"status-dot #{if up, do: "status-dot--green", else: "status-dot--red"}"} />
                <span class="flex-1"><%= s.name %></span>
                <span class="text-[11px] text-text-tertiary uppercase tracking-[0.08em]">
                  <%= if up, do: "up", else: "down" %>
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <button class="btn-primary" phx-click="show_details" phx-value-type="zrok" phx-value-id="_">
          Configure network
        </button>
        <button
          class="ghost-icon"
          phx-click="toggle_obfuscation"
          phx-value-obfuscated={to_string(!@obfuscated)}
          aria-label={if @obfuscated, do: "Show", else: "Hide"}
        >
          <.eye :if={!@obfuscated} size={18} />
          <.eye_slash :if={@obfuscated} size={18} />
        </button>
        <div class="relative">
          <button class="ghost-icon" phx-click="toggle_settings_menu" aria-label="Settings">
            <.settings size={18} />
          </button>
          <.settings_dropdown open={@settings_menu_open} />
        </div>
      </div>
    </div>
    """
  end
end

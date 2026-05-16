defmodule TunneldWeb.Live.Components.GaugeGrid do
  @moduledoc """
  System resource gauges: CPU, MEM, STORAGE, TEMP in a 2x2 grid inside a hero-card.
  Uses animated donut gauges with a LiveView hook.
  """
  use Phoenix.Component
  import TunneldWeb.Icons

  attr :cpu, :integer, default: 0
  attr :mem_pct, :integer, default: 0
  attr :mem_used, :string, default: "—"
  attr :mem_total, :string, default: "—"
  attr :storage_pct, :integer, default: 0
  attr :storage_used, :string, default: "—"
  attr :storage_total, :string, default: "—"
  attr :temp_value, :integer, default: 0
  attr :temp_max, :integer, default: 80

  def gauge_grid(assigns) do
    ~H"""
    <div class="hero-card p-0 overflow-hidden grid grid-cols-2 grid-rows-2 h-full">
      <div class="border-r border-b border-border">
        <.gauge_cell icon={:cpu} label="CPU" value={@cpu} max={100} suffix="%" />
      </div>
      <div class="border-b border-border">
        <.gauge_cell icon={:hard_drive} label="MEM" value={@mem_pct} max={100} suffix="%" />
      </div>
      <div class="border-r border-border">
        <.gauge_cell icon={:database} label="STORAGE" value={@storage_pct} max={100} suffix="%" />
      </div>
      <div>
        <.gauge_cell icon={:thermometer} label="TEMP" value={@temp_value} max={@temp_max} suffix="°" />
      </div>
    </div>
    """
  end

  attr :icon, :atom, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :max, :integer, default: 100
  attr :suffix, :string, default: "%"
  attr :sub, :string, default: ""

  defp gauge_cell(assigns) do
    val = if is_number(assigns.value), do: assigns.value, else: 0
    max_val = if is_number(assigns.max), do: assigns.max, else: 100
    shown = "#{val}#{assigns.suffix}"
    id = "gauge-#{assigns.label}"
    is_temp = assigns.label == "TEMP"
    danger_pct = if max_val > 0, do: val / max_val, else: 0
    danger_class = cond do
      is_temp and danger_pct >= 1.0 -> "text-red"
      is_temp and danger_pct >= 0.875 -> "text-orange-500"
      true -> "text-accent"
    end

    assigns = assign(assigns, val: val, shown: shown, id: id, danger_class: danger_class)

    ~H"""
    <div class="h-full flex flex-col items-center justify-center relative">
      <div class="absolute top-3.5 left-3.5 flex items-center gap-1.5 text-text-secondary">
        <%= case @icon do %>
          <% :cpu -> %><.cpu size={12} />
          <% :hard_drive -> %><.hard_drive size={12} />
          <% :database -> %><.database size={12} />
          <% :thermometer -> %><.thermometer size={12} />
        <% end %>
        <span class="text-[10px] tracking-[0.08em] uppercase font-medium text-text-secondary"><%= @label %></span>
      </div>

      <div
        id={@id}
        class="relative"
        phx-hook="Gauge"
        data-value={@val}
        data-max={@max}
        style="width: 120px; height: 120px;"
      >
        <svg width="120" height="120" style="transform: rotate(-90deg)">
          <circle cx="60" cy="60" r="55" fill="none" stroke="#1F1E2A" stroke-width="6" />
          <circle
            cx="60" cy="60" r="55"
            fill="none" stroke="currentColor" class={@danger_class}
            stroke-width="6" stroke-linecap="round"
            stroke-dasharray="345.6"
            stroke-dashoffset="345.6"
            data-ref="gauge-fg"
          />
        </svg>
        <div class="absolute inset-0 flex items-center justify-center font-mono text-[20px] font-medium text-text-primary -tracking-[0.02em]">
          <%= @shown %>
        </div>
      </div>
    </div>
    """
  end
end

defmodule TunneldWeb.Live.Components.InternetCard do
  @moduledoc """
  Upstream link status card with animated ring indicator.
  Clicking opens the ethernet sidebar.
  """
  use Phoenix.Component
  import TunneldWeb.CoreComponents, only: [icon: 1]
  import TunneldWeb.Icons

  attr :on, :boolean, default: false

  def internet_card(assigns) do
    ring_color = if assigns.on, do: "#2ECC71", else: "rgba(255,77,79,0.5)"
    label_color = if assigns.on, do: "#2ECC71", else: "#FF4D4F"
    box_shadow = if assigns.on, do: "0 0 32px rgba(46,204,113,0.40)", else: "none"
    animation = if assigns.on, do: "ringBreathe 2s ease-in-out infinite", else: "none"

    assigns = assign(assigns, ring_color: ring_color, label_color: label_color, box_shadow: box_shadow, animation: animation)

    ~H"""
    <div class="hero-card px-6 py-5 flex flex-col gap-3.5 cursor-pointer" phx-click="show_details" phx-value-type="ethernet" phx-value-id="_">
      <div class="flex justify-between items-center">
        <div class="text-[11px] tracking-[0.08em] uppercase text-text-secondary font-medium">
          INTERNET ACCESS
        </div>
        <span class="text-text-tertiary inline-flex">
          <.chevron_right size={14} />
        </span>
      </div>
      <div class="flex items-center justify-center flex-1">
        <div
          class="w-16 h-16 rounded-full border-[3px] flex items-center justify-center flex-shrink-0"
          style={"border-color: #{@ring_color}; box-shadow: #{@box_shadow}; animation: #{@animation}"}
        >
          <.icon name="hero-signal" class={"w-6 h-6 #{if @on, do: "text-green", else: "text-red"}"} />
        </div>
      </div>
    </div>
    """
  end
end

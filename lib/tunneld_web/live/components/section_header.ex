defmodule TunneldWeb.Live.Components.SectionHeader do
  @moduledoc """
  Reusable section header with purple accent underline and optional action buttons.
  """
  use Phoenix.Component

  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def section_header(assigns) do
    ~H"""
    <div class={["flex items-end justify-between mb-5", @class]}>
      <div>
        <h2 class="text-[22px] font-normal text-text-primary -tracking-[0.01em] m-0">
          <%= render_slot(@inner_block) %>
        </h2>
        <div class="h-px w-6 bg-accent mt-2" />
      </div>
      <div :if={@actions != []} class="flex gap-1">
        <%= render_slot(@actions) %>
      </div>
    </div>
    """
  end
end

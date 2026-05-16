defmodule TunneldWeb.Live.Components.HelpIcon do
  @moduledoc """
  Reusable help tooltip icon showing contextual explanations on hover.
  Uses a JS hook to render the tooltip as a portal to document.body
  so it is never clipped by parent containers or sidebars.
  """
  use Phoenix.Component

  attr :text, :string, required: true, doc: "Tooltip text to display on hover"
  attr :class, :string, default: nil

  def help_icon(assigns) do
    ~H"""
    <span
      id={"help-#{:erlang.unique_integer([:positive])}"}
      class={["inline-flex items-center justify-center w-4 h-4 rounded-full bg-accent/20 text-accent text-[10px] font-bold select-none cursor-help ml-3 shrink-0", @class]}
      data-help-text={@text}
      phx-hook="HelpTooltip"
    >?</span>
    """
  end
end

defmodule SentinelWeb.Live.Components.Services do
  @moduledoc """
  Running Services on the operating system and their availability
  """
  use SentinelWeb, :live_component

  def mount(_, _, socket) do
    {:ok, socket}
  end

  @doc """
  Render the services and their status
  """
  def render(assigns) do
    ~H"""
    <div class="p-5 sm:p-8 md:p-10">
      Status
    </div>
    """
  end
end

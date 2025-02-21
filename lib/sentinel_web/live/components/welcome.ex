defmodule SentinelWeb.Live.Components.Welcome do
  @moduledoc """
  The welcome message to welcome the user. This will contain message and some details potentially.
  """
  use SentinelWeb, :live_component

  def mount(_, _, socket) do
    {:ok, socket}
  end

  @doc """
  Show the message and subtext that could be used as subtext information (Disabled AI Overview)
  """
  def render(assigns) do
    ~H"""
    <div class="p-5 sm:p-8 md:p-10">
      <div class="text-7xl font-medium bg-gradient-to-r from-gray-1 to-white bg-clip-text text-transparent">
        Welcome
      </div>
      <div class="mt-3 text-2xl text-gray-1">...</div>
    </div>
    """
  end
end

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
    <div class="p-5">
      <div class="text-6xl font-medium bg-gradient-to-r from-slate-300 to-slate-600 bg-clip-text text-transparent">
        sentinel.local
      </div>
      <%!-- <div class="my-3 text-3xl text-white font-medium">Some information here about the overview</div> --%>
    </div>
    """
  end
end

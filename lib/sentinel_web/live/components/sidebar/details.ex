defmodule SentinelWeb.Live.Components.Sidebar.Details do
  @moduledoc """
  The list of sidebar details to render
  """
  use SentinelWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:sidebar")
    end
    {:ok, socket}
  end

  def update(%{ view: view } = assigns, socket) do
    socket =
      socket
      |> assign(view: view)
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  # Render the Empty state of the view
  @spec render(%{:view => :system_overview | boolean(), optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{ view: view } = assigns) when view in [:system_overview, false, true] do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <.icon class="w-[50px] h-[50px] text-green" name="hero-shield-check" />
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">System is running as expected.</h1>

      <%!-- TODO: add overflow here for content --%>
    </div>
    """
  end
end

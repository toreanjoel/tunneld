defmodule SentinelWeb.Live.Components.Sidebar.Details do
  @moduledoc """
  The list of sidebar details to render
  """
  use SentinelWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:details")
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

  @spec render(%{:view => :system_overview, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{ view: :system_overview } = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <.icon class="w-[50px] h-[50px] text-green" name="hero-shield-check" />
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">System is running as expected.</h1>

      <%!-- TODO: add overflow here for content --%>
    </div>
    """
  end

  @spec render(%{:view => :node, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{ view: :node } = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">node</h1>

      <%!-- TODO: add overflow here for content --%>
    </div>
    """
  end

  @spec render(%{:view => :service, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{ view: :service } = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">service</h1>

      <%!-- TODO: add overflow here for content --%>
    </div>
    """
  end

  @spec render(%{:view => :device, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{ view: :device } = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">device</h1>

      <%!-- TODO: add overflow here for content --%>
    </div>
    """
  end

  @spec render(%{:view => :blacklist, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{ view: :blacklist } = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">blacklist</h1>

      <%!-- TODO: add overflow here for content --%>
    </div>
    """
  end

  @spec render(%{:view => :logs, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{ view: :logs } = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">logs</h1>

      <pre class="text-sm text-white">
        <%= inspect(@data.logs, pretty: true) %>
      </pre>
    </div>
    """
  end
end

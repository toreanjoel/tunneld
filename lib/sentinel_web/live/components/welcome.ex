defmodule SentinelWeb.Live.Components.Welcome do
  @moduledoc """
  The welcome message to welcome the user. This will contain message and some details potentially.
  """
  use SentinelWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:welcome")
    end
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(data: Map.get(assigns, :data, %{}))}
  end

  @doc """
  Show the message and subtext that could be used as subtext information (Disabled AI Overview)
  """
  def render(assigns) do
    assigns = assigns |> assign(version: Map.get(assigns.data, :version, Application.get_env(:sentinel, :version)))

    ~H"""
    <div class="py-5">
      <div class="text-4xl font-medium bg-gradient-to-r from-slate-300 to-slate-600 bg-clip-text text-transparent">
        sentinel.local
      </div>
      <div class="text-lg text-gray-2 font-light">
        <%= @version %>
      </div>
    </div>
    """
  end
end

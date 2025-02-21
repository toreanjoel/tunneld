defmodule SentinelWeb.Live.Components.Devices do
  @moduledoc """
  The connected devices to the network and their access
  """
  use SentinelWeb, :live_component

  def mount(_, _, socket) do
    {:ok, socket}
  end

  @doc """
  Render the devices connected to the network
  """
  def render(assigns) do
    ~H"""
    <div class="p-5 sm:p-8 md:p-10">
      Devices
    </div>
    """
  end
end

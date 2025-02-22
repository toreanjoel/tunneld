defmodule SentinelWeb.Live.Components.Services do
  @moduledoc """
  Running Services on the operating system and their availability
  """
  use SentinelWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:services")
    end
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(data: Map.get(assigns, :data, %{}))}
  end

  @doc """
  Render the services and their status
  """
  def render(assigns) do
    ~H"""
    <div class="p-5">
      <div class="mb-5">
        <div class="text-xl text-gray-1 font-medium">Services</div>
        <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
      </div>
      <div class="grid grid-cols-2 xl:grid-cols-4 gap-2">
        <div phx-click="show_details" phx-value-type={"service"} phx-value-id={"dhcpcd"} class="bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
          <div class="w-[13px] h-[13px] rounded-full bg-yellow"></div>
          <div class="text-sm truncate">DHCP</div>
        </div>
        <div phx-click="show_details" phx-value-type={"service"} phx-value-id={"dnsmasq"} class="bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
          <div class="w-[13px] h-[13px] rounded-full bg-red"></div>
          <div class="text-sm truncate">DNS</div>
        </div>
        <div phx-click="show_details" phx-value-type={"service"} phx-value-id={"dnscrypt-proxy"} class="bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
          <div class="w-[13px] h-[13px] rounded-full bg-gray-1"></div>
          <div class="text-sm truncate">DoH</div>
        </div>
        <div phx-click="show_details" phx-value-type={"service"} phx-value-id={"hostapd"} class="bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
          <div class="w-[13px] h-[13px] rounded-full bg-green"></div>
          <div class="text-sm truncate">WiFi</div>
        </div>
      </div>
    </div>
    """
  end
end

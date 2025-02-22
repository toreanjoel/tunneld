defmodule SentinelWeb.Live.Components.Devices do
  @moduledoc """
  The connected devices to the network and their access
  """
  use SentinelWeb, :live_component
  alias Sentinel.Servers.Whitelist

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:devices")
    end

    {:ok, socket |> assign(loading: true)}
  end

  def update(assigns, socket) do
    new_devices =
      assigns
      |> Map.get(:data, %{})
      |> Map.get(:devices, [])

    socket =
      socket
      |> assign(devices: new_devices)
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the devices connected to the network.
  """
  def render(assigns) do
    ~H"""
    <div class="p-5">
      <div class="mb-5 flex flex-row">
        <div class="flex-1">
          <div class="text-xl text-gray-1 font-medium">Devices</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div class="grid grid-cols-2 gap-1">
          <div phx-click="show_details" phx-value-type="blacklist" phx-value-id="_" class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150">
            <.icon class="w-4 h-4" name="hero-no-symbol" />
            <div class="truncate text-xs text-gray-1">Block List</div>
          </div>
          <div phx-click="show_details" phx-value-type="logs" phx-value-id="_" class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150">
            <.icon class="w-4 h-4" name="hero-circle-stack" />
            <div class="truncate text-xs text-gray-1">Log Backups</div>
          </div>
        </div>
      </div>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <%= for device <- @devices do %>
          <div phx-click="show_details" phx-value-type="device" phx-value-id={device.ip} class="p-4 flex flex-col bg-secondary rounded-lg w-full h-[130px] hover:bg-secondary cursor-pointer">
            <div class="flex flex-row">
              <div class="grow">
                <.icon class="w-6 h-6 text-gray-1" name={get_device_icon(device.type)} />
              </div>
              <label
                phx-click="toggle_access"
                phx-target={@myself}
                phx-value-mac={device.mac}
                class="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" class="sr-only peer" checked={device.access} />
                <div class="w-9 h-5 bg-light_purple rounded-full peer-checked:bg-purple relative after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-light_purple after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-4"></div>
              </label>
            </div>
            <div class="grow" />
            <div class="text-sm"><%= device.hostname %></div>
            <div class="text-xs"><%= device.ip %></div>
            <div class="text-xs"><%= device.mac %></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Handle toggle event for granting/revoking access.
  """
  def handle_event("toggle_access", %{"mac" => mac}, socket) do
    device = Enum.find(socket.assigns.devices, fn d -> d.mac == mac end)

    if device do
      if device.access do
        IO.puts("Revoking access for device with MAC: #{mac}")
        Whitelist.remove_device_access(mac)
      else
        IO.puts("Granting access for device with MAC: #{mac}")
        Whitelist.add_device_access(%{
          hostname: device.hostname,
          ip: device.ip,
          mac: device.mac,
          ttl: nil,
          status: "granted"
        })
      end
    end

    {:noreply, socket}
  end

  defp get_device_icon("tv"), do: "hero-tv"
  defp get_device_icon("phone"), do: "hero-phone"
  defp get_device_icon("pc"), do: "hero-computer-desktop"
  defp get_device_icon(_), do: "hero-question-mark-circle"
end

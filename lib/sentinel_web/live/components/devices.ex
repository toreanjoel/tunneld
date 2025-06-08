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
    new_data = Map.get(assigns, :data, %{})

    # Only turn off loading when we have a non-empty list of devices
    new_loading =
      case Map.get(new_data, :devices, []) do
        [] -> true
        _ -> false
      end

    socket =
      socket
      |> assign(data: new_data)
      |> assign(loading: new_loading)

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
        <div class="grid grid-cols-1 gap-1">
          <%!-- SSH interaction? --%>
          <%!-- <div
            phx-click="modal_open"
            phx-value-modal_title="SSH Session Request"
            phx-value-modal_body={
              Jason.encode!(%{
                "type" => "schema",
                "data" => Sentinel.Schema.SshSession.data(),
                "default_values" => %{
                  ip: Sentinel.Servers.Devices.fetch_devices() |> Enum.map(fn item -> item.ip end)
                },
                "action" => "open_ssh_session"
              })
            }
            class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md text-gray-1"
          >
            <.icon class="w-4 h-4" name="hero-command-line" />
            <div class="truncate text-xs">SSH Session</div>
          </div> --%>

          <div
            phx-click="trigger_action"
            phx-value-action="open_terminal"
            phx-value-data={Jason.encode!(%{})}
            class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
          >
            <.icon class="w-4 h-4" name="hero-command-line" />
            <div class="truncate text-xs">Terminal</div>
          </div>
        </div>
      </div>

      <%!-- Loading indicator --%>
      <div :if={@loading} class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div class="p-4 flex flex-col bg-secondary rounded-lg w-full h-[130px] opacity-10">
          <div class="grow">
            <.icon class="w-10 h-10 text-white" name="hero-computer-desktop" />
          </div>
          <div class="grow" />
          <div class="text-md text-white">Scanning Devices...</div>
        </div>
      </div>

      <%!-- Content after loading --%>
      <div :if={!@loading} class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <%= for device <- Map.get(@data, :devices, []) do %>
          <div
            class="p-4 flex flex-col bg-secondary rounded-lg w-full h-[130px] hover:bg-secondary"
            style="animation: fadeIn 0.5s ease-out forwards;"
          >
            <div class="flex flex-row">
              <div class="grow truncate ellipsis">
                <div class="text-sm truncate"><%= device.hostname %></div>
              </div>
              <div>
                <label
                  phx-click="toggle_access"
                  phx-target={@myself}
                  phx-value-mac={device.mac}
                  class="relative inline-flex items-center cursor-pointer"
                >
                  <input type="checkbox" class="sr-only peer" checked={device.access} />
                  <div class="w-9 h-5 bg-light_purple rounded-full peer-checked:bg-purple relative after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-light_purple after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-4">
                  </div>
                </label>
              </div>
            </div>
            <div class="grow" />
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
    data = socket.assigns.data
    device = Enum.find(data.devices, fn d -> d.mac == mac end)

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
end

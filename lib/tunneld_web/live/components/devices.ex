defmodule TunneldWeb.Live.Components.Devices do
  @moduledoc """
  The connected devices to the network and their access
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    {:ok, socket |> assign(loading: true)}
  end

  def update(assigns, socket) do
    new_data = Map.get(assigns, :data, %{})
    devices = Map.get(new_data, :devices, [])

    devices =
      Enum.map(devices, fn d ->
        Map.put(d, :expose_allowed, Tunneld.Servers.ExposeAllowed.allowed?(d.mac))
      end)

    new_data = Map.put(new_data, :devices, devices)

    # Only turn off loading when we have a non-empty list of devices
    new_loading =
      case devices do
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
    <div class="p-3 md:p-5">
      <div class="mb-4 md:mb-5 flex flex-row">
        <div class="flex-1">
          <div class="text-lg md:text-xl text-gray-1 font-medium">Devices</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div class="grid grid-cols-1 gap-1">
          <%!-- This is the button above the devices --%>
        </div>
      </div>

      <%!-- Loading indicator --%>
      <div :if={@loading} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <div class="p-4 flex flex-col bg-secondary rounded-lg w-full h-[130px] opacity-10">
          <div class="grow">
            <.icon class="w-10 h-10 text-white" name="hero-computer-desktop" />
          </div>
          <div class="grow" />
          <div class="text-md text-white">Scanning Devices...</div>
        </div>
      </div>

      <%!-- Content after loading --%>
      <div :if={!@loading} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <%= for device <- Map.get(@data, :devices, []) do %>
          <div
            class="p-4 flex flex-col bg-secondary rounded-lg w-full h-[130px] hover:bg-secondary"
            style="animation: fadeIn 0.5s ease-out forwards;"
          >
            <div class="flex flex-row gap-2">
              <div class="flex-1 truncate ellipsis"><%= device.hostname %></div>
              <div
                phx-click="modal_open"
                phx-value-modal_title={if device.expose_allowed, do: "Revoke Quick Expose?", else: "Allow Quick Expose?"}
                phx-value-modal_body={
                  Jason.encode!(%{
                    "type" => "string",
                    "data" =>
                      if device.expose_allowed do
                        "This device will no longer be able to create public shares via Quick Expose."
                      else
                        "This device will be able to run curl commands to create public shares via Quick Expose."
                      end
                  })
                }
                phx-value-modal_actions={
                  Jason.encode!(%{
                    "title" => (if device.expose_allowed, do: "Revoke", else: "Allow"),
                    "payload" => %{
                      "type" => (if device.expose_allowed, do: "revoke_device_expose", else: "allow_device_expose"),
                      "data" => %{
                        "mac" => device.mac
                      }
                    }
                  })
                }
                phx-click-loading="opacity-50 cursor-wait"
                class="cursor-pointer"
              >
                <.icon name="hero-link" class={if device.expose_allowed, do: "h-4 w-4 text-green", else: "h-4 w-4 text-gray-2"} />
              </div>
              <div
                phx-click="modal_open"
                phx-value-modal_title="Revoke devices IP address?"
                phx-value-modal_body={
                  Jason.encode!(%{
                    "type" => "string",
                    "data" =>
                      "This will release the device #{device.hostname} (#{device.ip}). The device will get a new ip address when connecting"
                  })
                }
                phx-value-modal_actions={
                  Jason.encode!(%{
                    "title" => "Revoke",
                    "payload" => %{
                      "type" => "revoke_release_ip",
                      "data" => %{
                        "mac" => device.mac
                      }
                    }
                  })
                }
                phx-click-loading="opacity-50 cursor-wait"
                class="cursor-pointer"
              >
                <.icon name="hero-x-mark-solid" class="h-4 w-4 text-red" />
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
end

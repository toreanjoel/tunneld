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
    obfuscated = Map.get(assigns, :obfuscated, false)

    devices =
      Enum.map(devices, fn d ->
        d
        |> Map.put(:expose_allowed, Tunneld.Servers.ExposeAllowed.allowed?(d.mac))
        |> Map.put(:tags, Tunneld.Servers.DeviceTags.get_tags(d.mac))
      end)

    new_data = Map.put(new_data, :devices, devices)

    socket =
      socket
      |> assign_new(:obfuscated, fn -> false end)
      |> assign(:obfuscated, obfuscated)

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
            class="p-4 flex flex-col bg-secondary rounded-lg w-full min-h-[130px] h-auto hover:bg-secondary"
            style="animation: fadeIn 0.5s ease-out forwards;"
          >
            <div class="flex flex-row gap-2">
              <div class="flex-1 truncate ellipsis"><%= mask(@obfuscated, device.hostname) %></div>
              <div
                phx-click="modal_open"
                phx-value-modal_title={"Manage tags for #{device.hostname}"}
                phx-value-modal_description={if device.tags != [], do: "Current tags: #{Enum.join(device.tags, ", ")}", else: "No tags yet. Add one below."}
                phx-value-modal_body={
                  Jason.encode!(%{
                    "type" => "schema",
                    "data" => Tunneld.Schema.data(:device_tag, %{hostname: device.hostname}),
                    "default_values" => %{
                      "mac" => device.mac
                    },
                    "action" => "add_device_tag"
                  })
                }
                phx-click-loading="opacity-50 cursor-wait"
                class="cursor-pointer"
              >
                <.icon name="hero-tag" class={if device.tags != [], do: "h-4 w-4 text-blue-400", else: "h-4 w-4 text-gray-2"} />
              </div>
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
            <div class={if device.tags != [], do: "grow-0 h-1", else: "grow"} />
            <div :if={device.tags != []} class="flex flex-wrap gap-1 mb-1 pt-1">
              <%= for tag <- Enum.take(device.tags, 2) do %>
                <span class="group px-1.5 py-0.5 text-[10px] bg-blue-900/60 text-blue-200 rounded border border-blue-700/40 flex items-center gap-1 shrink-0" title={tag}>
                  <span class="truncate max-w-[90px]"><%= tag %></span>
                  <span
                    phx-click="trigger_action"
                    phx-value-action="remove_device_tag"
                    phx-value-data={Jason.encode!(%{"mac" => device.mac, "tag" => tag})}
                    class="cursor-pointer opacity-60 group-hover:opacity-100 transition-opacity shrink-0"
                  >
                    <.icon name="hero-x-mark" class="h-2.5 w-2.5" />
                  </span>
                </span>
              <% end %>
              <%= if length(device.tags) > 2 do %>
                <span class="px-1.5 py-0.5 text-[10px] text-gray-400">+<%= length(device.tags) - 2 %></span>
              <% end %>
            </div>
            <div class="mt-auto">
              <div class="text-xs text-gray-400"><%= mask(@obfuscated, device.ip) %></div>
              <div class="text-xs text-gray-400"><%= mask(@obfuscated, device.mac) %></div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end

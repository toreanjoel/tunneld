defmodule TunneldWeb.Live.Components.Devices do
  @moduledoc """
  The connected devices to the network and their access
  """
  use TunneldWeb, :live_component
  import TunneldWeb.Live.Components.SectionHeader
  import TunneldWeb.Live.Components.HelpIcon

  def mount(socket) do
    # Paint from the server's warm cache immediately, then ask for a fresh read.
    # The broadcast that follows arrives as a normal update/2.
    current = Tunneld.Servers.Devices.current()
    Tunneld.Servers.Devices.sync_now()

    {:ok, socket |> assign(loaded: Map.get(current, :loaded, false)) |> assign(data: current)}
  end

  def update(assigns, socket) do
    # The parent renders this component with no `:data` when the panel is opened
    # (the payload only arrives on the next broadcast). Defaulting to `%{}` there
    # emptied the list and flipped the view back to "Scanning Devices..." on
    # every open. Absent data means "unchanged", not "none".
    new_data = Map.get(assigns, :data) || Map.get(socket.assigns, :data) || %{}
    devices = Map.get(new_data, :devices, [])
    obfuscated = Map.get(assigns, :obfuscated, false)

    # Reachability is probed by Tunneld.Servers.Devices, off the render path.
    devices =
      Enum.map(devices, fn d ->
        d
        |> Map.put(:expose_allowed, Tunneld.Servers.ExposeAllowed.allowed?(d.mac))
        |> Map.put(:tags, Tunneld.Servers.DeviceTags.get_tags(d.mac))
        |> Map.put(:online, Map.get(d, :online, false))
        |> Map.put(:egress, Tunneld.Egress.device_egress(d.ip) || "local")
      end)

    new_data = Map.put(new_data, :devices, devices)

    # "Loading" means "we have not read the leases yet", not "the list is empty".
    # A subnet with no devices is a real answer and should say so.
    loaded = Map.get(new_data, :loaded, false) or Map.get(socket.assigns, :loaded, false)

    remote_features = Tunneld.Config.remote_features?()

    socket =
      socket
      |> assign_new(:obfuscated, fn -> false end)
      |> assign(:obfuscated, obfuscated)
      |> assign(:remote_features, remote_features)
      |> assign(
        :egress_machines,
        if(remote_features, do: Map.get(assigns, :egress_machines, []), else: [])
      )
      |> assign(data: new_data)
      |> assign(loaded: loaded)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="p-3 md:p-5">
      <.section_header>
        Devices<.help_icon text="Devices discovered on your LAN subnet via DHCP leases. Each device automatically gets an IP from dnsmasq. Use Quick Expose to let devices create local resources via a curl command. Revoke IP to release the DHCP lease. Egress routes traffic through an exit machine instead of the gateway's upstream; pick 'Local' to use the gateway directly." />
      </.section_header>

      <div :if={!@loaded} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <div class="p-4 flex flex-col bg-surface rounded-lg w-full h-[130px] opacity-10">
          <div class="grow">
            <.icon class="w-10 h-10 text-text-primary" name="hero-computer-desktop" />
          </div>
          <div class="grow" />
          <div class="text-md text-text-primary">Scanning Devices...</div>
        </div>
      </div>

      <div
        :if={@loaded and Map.get(@data, :devices, []) == []}
        class="text-sm text-text-tertiary py-4"
      >
        No devices are holding a DHCP lease on this subnet.
      </div>

      <div
        :if={@loaded}
        class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3 items-start"
      >
        <%= for device <- Map.get(@data, :devices, []) do %>
          <div
            class="p-4 flex flex-col bg-surface border border-border rounded-lg w-full min-h-[130px] h-auto transition-colors duration-[120ms] hover:bg-[#17161F] hover:border-[#2A2838]"
            style="animation: fadeIn 0.5s ease-out forwards;"
          >
            <div class="flex flex-row gap-2">
              <div class="flex-1 flex items-center gap-1.5 min-w-0">
                <span class="truncate"><%= mask(@obfuscated, device.hostname) %></span>
                <span class={"status-dot shrink-0 #{if !@obfuscated && Map.get(device, :online, false), do: "status-dot--green", else: "status-dot--gray"}"} />
                <%= if @remote_features && device.egress != "local" do %>
                  <span class="px-1.5 py-0.5 rounded-full bg-accent/20 text-accent uppercase text-[9px] font-medium shrink-0">
                    via exit
                  </span>
                <% end %>
              </div>
              <div
                phx-click="modal_open"
                phx-value-modal_title={"Manage tags for #{device.hostname}"}
                phx-value-modal_description={
                  if device.tags != [],
                    do:
                      "Current tags: #{Enum.join(device.tags, ", ")}. Enter a new tag below to append.",
                    else: "No tags yet. Add one below."
                }
                phx-value-modal_body={
                  Jason.encode!(%{
                    "type" => "schema",
                    "data" =>
                      Tunneld.Schema.data(:device_tag, %{
                        hostname: device.hostname,
                        current_tags: device.tags
                      }),
                    "default_values" => %{
                      "mac" => device.mac
                    },
                    "action" => "add_device_tag"
                  })
                }
                phx-click-loading="opacity-50 cursor-wait"
                class="cursor-pointer"
              >
                <.icon
                  name="hero-tag"
                  class={
                    if device.tags != [],
                      do: "h-4 w-4 text-blue-400",
                      else: "h-4 w-4 text-text-secondary"
                  }
                />
              </div>
              <div
                phx-click="modal_open"
                phx-value-modal_title={
                  if device.expose_allowed, do: "Revoke Quick Expose?", else: "Allow Quick Expose?"
                }
                phx-value-modal_body={
                  Jason.encode!(%{
                    "type" => "string",
                    "data" =>
                      if device.expose_allowed do
                        "This device will no longer be able to create resources via Quick Expose."
                      else
                        "This device will be able to run curl commands to create resources via Quick Expose."
                      end
                  })
                }
                phx-value-modal_actions={
                  Jason.encode!(%{
                    "title" => if(device.expose_allowed, do: "Revoke", else: "Allow"),
                    "payload" => %{
                      "type" =>
                        if(device.expose_allowed,
                          do: "revoke_device_expose",
                          else: "allow_device_expose"
                        ),
                      "data" => %{
                        "mac" => device.mac
                      }
                    }
                  })
                }
                phx-click-loading="opacity-50 cursor-wait"
                class="cursor-pointer"
              >
                <.icon
                  name="hero-link"
                  class={
                    if device.expose_allowed,
                      do: "h-4 w-4 text-green",
                      else: "h-4 w-4 text-text-secondary"
                  }
                />
              </div>

              <%!-- Wake is only meaningful from here: the magic packet has to be
                   broadcast inside this subnet, which the gateway can do and a
                   WireGuard client fundamentally cannot. --%>
              <div
                phx-click="trigger_action"
                phx-value-action="wake_device"
                phx-value-data={Jason.encode!(%{"mac" => device.mac, "hostname" => device.hostname})}
                phx-click-loading="opacity-50 cursor-wait"
                class="cursor-pointer"
                title={"Send a wake-on-LAN packet to #{device.hostname}"}
              >
                <.icon
                  name="hero-bolt"
                  class={
                    if Map.get(device, :online, false),
                      do: "h-4 w-4 text-text-secondary",
                      else: "h-4 w-4 text-yellow"
                  }
                />
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
            <div :if={device.tags != []} class="flex flex-wrap gap-1 mb-1 pt-1">
              <%= for tag <- device.tags |> Enum.sort_by(& &1) |> Enum.take(2) do %>
                <span
                  class={"group px-1.5 py-0.5 text-[10px] rounded border flex items-center gap-1 shrink-0 " <> tag_classes(tag)}
                  title={tag}
                >
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
                <span class="px-1.5 py-0.5 text-[10px] text-text-tertiary">
                  +<%= length(device.tags) - 2 %>
                </span>
              <% end %>
            </div>
            <div class="mt-auto pt-3">
              <div :if={@remote_features} class="flex items-center justify-between gap-2 mb-1.5 px-1">
                <span class="text-[10px] uppercase tracking-wide text-text-tertiary">
                  Egress
                </span>
                <form phx-change="set_device_egress" phx-target={@myself}>
                  <input type="hidden" name="ip" value={device.ip} />
                  <select
                    name="egress"
                    title="Route this device's traffic through an exit machine"
                    class="cursor-pointer pl-2 pr-6 py-1 text-[10px] rounded border bg-surface-2 text-text-secondary border-border"
                  >
                    <option value="local" selected={device.egress == "local"}>Local</option>
                    <%= for {mid, mname} <- @egress_machines do %>
                      <option value={mid} selected={device.egress == mid}><%= mname %></option>
                    <% end %>
                  </select>
                </form>
              </div>
              <div class="text-xs text-text-tertiary flex items-center gap-1.5 justify-between px-1">
                <span><%= mask(@obfuscated, device.ip) %></span>
              </div>
              <div class="text-xs text-text-tertiary px-1"><%= mask(@obfuscated, device.mac) %></div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # The egress dropdown lives on each device card. The actual routing logic is
  # owned by the parent dashboard (set_device_egress), so forward the change
  # there. The select sends the chosen value as "value"; ip comes from phx-value-ip.
  def handle_event("set_device_egress", %{"ip" => ip, "egress" => egress}, socket) do
    # egress == "local" reverts to the gateway's own upstream; otherwise route
    # the device out through the named exit machine. Done here (not forwarded to
    # the parent) because this component is re-rendered via send_update and has
    # no reliable parent_pid.
    result =
      if egress == "local" do
        # Revert to the gateway's own upstream: unroute the device from its
        # current exit machine (if any).
        case Tunneld.Egress.device_egress(ip) do
          nil ->
            :ok

          mid ->
            case Tunneld.Machines.get(mid) do
              {:ok, machine} -> Tunneld.Egress.unroute_device(machine, ip)
              _ -> :ok
            end
        end
      else
        case Tunneld.Machines.get(egress) do
          {:ok, machine} -> Tunneld.Egress.route_device(machine, ip)
          _ -> {:error, "exit machine not found"}
        end
      end

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: if(result == :ok or match?({:ok, _}, result), do: :info, else: :error),
      message: format_egress_result(result, ip, egress)
    })

    # Re-read now so the card shows the new egress immediately instead of
    # waiting out the poll interval.
    Tunneld.Servers.Devices.sync_now()

    {:noreply, socket}
  end

  defp tag_classes(_tag), do: "bg-surface-2 text-text-secondary border-border"

  defp format_egress_result(:ok, ip, "local"), do: "Routing #{ip} through gateway"
  defp format_egress_result(:ok, ip, egress), do: "Routing #{ip} through #{egress}"
  defp format_egress_result({:ok, _}, ip, "local"), do: "Routing #{ip} through gateway"
  defp format_egress_result({:ok, _}, ip, egress), do: "Routing #{ip} through #{egress}"

  defp format_egress_result({:error, reason}, ip, _) when is_binary(reason),
    do: "Could not route #{ip}: #{reason}"

  defp format_egress_result({:error, _}, ip, _), do: "Could not route #{ip}"
  defp format_egress_result(_, ip, _), do: "Egress updated for #{ip}"
end

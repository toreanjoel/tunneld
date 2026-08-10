defmodule TunneldWeb.Live.Components.Devices do
  @moduledoc """
  The connected devices to the network and their access
  """
  use TunneldWeb, :live_component
  import TunneldWeb.Live.Components.SectionHeader
  import TunneldWeb.Live.Components.HelpIcon

  def mount(socket) do
    {:ok, socket |> assign(loading: true)}
  end

  def update(assigns, socket) do
    new_data = Map.get(assigns, :data, %{})
    devices = Map.get(new_data, :devices, [])
    obfuscated = Map.get(assigns, :obfuscated, false)

    probe_cache = Map.get(socket.assigns, :probe_cache, %{})
    now = System.monotonic_time(:second)

    {devices, probe_cache} =
      Enum.reduce(devices, {[], probe_cache}, fn d, {acc, cache} ->
        online =
          case Map.get(cache, d.mac) do
            %{at: at, online: val} when now - at < 30 -> val
            _ -> probe_online(d.ip)
          end

        cache = Map.put(cache, d.mac, %{at: now, online: online})
        d =
          d
          |> Map.put(:expose_allowed, Tunneld.Servers.ExposeAllowed.allowed?(d.mac))
          |> Map.put(:tags, Tunneld.Servers.DeviceTags.get_tags(d.mac))
          |> Map.put(:online, online)
          |> Map.put(:egress, Tunneld.Egress.device_egress(d.ip) || "local")
        {[d | acc], cache}
      end)

    devices = Enum.reverse(devices)
    new_data = Map.put(new_data, :devices, devices)

    socket =
      socket
      |> assign_new(:obfuscated, fn -> false end)
      |> assign(:obfuscated, obfuscated)
      |> assign(:probe_cache, probe_cache)
      |> assign(:egress_machines, Map.get(assigns, :egress_machines, []))

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
      <.section_header>Devices<.help_icon text="Devices discovered on your LAN subnet via DHCP leases. Each device automatically gets an IP from dnsmasq. Use Quick Expose to let devices create local resources via a curl command. Revoke IP to release the DHCP lease." /></.section_header>

      <div :if={@loading} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <div class="p-4 flex flex-col bg-surface rounded-lg w-full h-[130px] opacity-10">
          <div class="grow">
            <.icon class="w-10 h-10 text-text-primary" name="hero-computer-desktop" />
          </div>
          <div class="grow" />
          <div class="text-md text-text-primary">Scanning Devices...</div>
        </div>
      </div>

      <div :if={!@loading} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <%= for device <- Map.get(@data, :devices, []) do %>
          <div
            class="p-4 flex flex-col bg-surface border border-border rounded-lg w-full min-h-[130px] h-auto transition-colors duration-[120ms] hover:bg-[#17161F] hover:border-[#2A2838]"
            style="animation: fadeIn 0.5s ease-out forwards;"
          >
            <div class="flex flex-row gap-2">
              <div class="flex-1 flex items-center gap-1.5 min-w-0">
                <span class="truncate"><%= mask(@obfuscated, device.hostname) %></span>
                <span class={"status-dot shrink-0 #{if !@obfuscated && Map.get(device, :online, false), do: "status-dot--green", else: "status-dot--gray"}"} />
                <%= if device.egress != "local" do %>
                  <span class="px-1.5 py-0.5 rounded-full bg-accent/20 text-accent uppercase text-[9px] font-medium shrink-0">via exit</span>
                <% end %>
              </div>
              <div
                phx-click="modal_open"
                phx-value-modal_title={"Manage tags for #{device.hostname}"}
                phx-value-modal_description={if device.tags != [], do: "Current tags: #{Enum.join(device.tags, ", ")}. Enter a new tag below to append.", else: "No tags yet. Add one below."}
                phx-value-modal_body={
                  Jason.encode!(%{
                    "type" => "schema",
                    "data" => Tunneld.Schema.data(:device_tag, %{hostname: device.hostname, current_tags: device.tags}),
                    "default_values" => %{
                      "mac" => device.mac
                    },
                    "action" => "add_device_tag"
                  })
                }
                phx-click-loading="opacity-50 cursor-wait"
                class="cursor-pointer"
              >
                <.icon name="hero-tag" class={if device.tags != [], do: "h-4 w-4 text-blue-400", else: "h-4 w-4 text-text-secondary"} />
              </div>
              <div
                phx-click="modal_open"
                phx-value-modal_title={if device.expose_allowed, do: "Revoke Quick Expose?", else: "Allow Quick Expose?"}
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
                <.icon name="hero-link" class={if device.expose_allowed, do: "h-4 w-4 text-green", else: "h-4 w-4 text-text-secondary"} />
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
              <%= for tag <- device.tags |> Enum.sort_by(& &1) |> Enum.take(2) do %>
                <span class={"group px-1.5 py-0.5 text-[10px] rounded border flex items-center gap-1 shrink-0 " <> tag_classes(tag)} title={tag}>
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
                <span class="px-1.5 py-0.5 text-[10px] text-text-tertiary">+<%= length(device.tags) - 2 %></span>
              <% end %>
            </div>
            <div class="mt-auto pt-3 border-t border-border/50">
              <div class="flex items-center justify-between gap-2 mb-1.5 px-1">
                <span class="flex items-center text-[10px] uppercase tracking-wide text-text-tertiary">
                  Egress
                  <.help_icon
                    class="ml-1"
                    text="Route this device's internet traffic out through an exit machine (e.g. a VM) instead of the gateway's own upstream. Pick 'Local' to use the gateway directly."
                  />
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
        :ok
      else
        case Tunneld.Machines.get(egress) do
          {:ok, machine} -> Tunneld.Egress.route_device(machine, ip)
          _ -> {:error, "exit machine not found"}
        end
      end

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: if(result == :ok or match?({:ok, _}, result), do: :info, else: :error),
      message: "Egress for #{ip}: #{inspect(result)}"
    })

    {:noreply, socket}
  end

  defp tag_classes(_tag), do: "bg-surface-2 text-text-secondary border-border"

  defp probe_online(ip) do
    mock? = Application.get_env(:tunneld, :mock_data, false)
    if mock? do
      true
    else
      case System.cmd("ping", ["-c", "1", "-W", "1", ip], stderr_to_stdout: true) do
        {_, 0} -> true
        _ -> false
      end
    end
  rescue
    _ -> false
  end
end

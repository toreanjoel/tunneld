defmodule TunneldWeb.Live.Components.DevicesSummary do
  @moduledoc """
  Devices summary card showing subnet device count with a "View all devices"
  toggle button that shows/hides a full-page device grid.
  """
  use Phoenix.Component
  import TunneldWeb.Icons
  import TunneldWeb.Live.Components.SectionHeader

  attr :count, :integer, default: 0
  attr :devices, :list, default: []
  attr :obfuscated, :boolean, default: false
  attr :devices_expanded, :boolean, default: false

  def devices_summary(assigns) do
    ~H"""
    <section class="mt-12">
      <.section_header>Devices on subnet</.section_header>
      <div class="bg-surface border border-border rounded-xl p-6 h-24 flex items-center justify-between">
        <div class="flex items-center gap-5">
          <span class="text-text-secondary inline-flex">
            <.monitor size={32} />
          </span>
          <span class="text-[28px] text-text-primary font-medium -tracking-[0.02em]">
            <%= @count %>
          </span>
          <span class="text-sm text-text-secondary leading-[1.3] max-w-[110px]">
            devices on subnet
          </span>
        </div>
        <button class="ghost-btn" phx-click="toggle_devices_expanded">
          <%= if @devices_expanded, do: "Back to dashboard", else: "View all devices" %>
          <.chevron_right size={16} />
        </button>
      </div>

      <div :if={@devices_expanded} class="mt-16">
        <.section_header>All devices</.section_header>
        <div :if={Enum.empty?(@devices)} class="text-text-tertiary text-sm py-8 text-center">
          No devices found
        </div>
        <div :if={!Enum.empty?(@devices)} class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <%= for device <- @devices do %>
            <% device_tags = Map.get(device, :tags, []) %>
            <div class="bg-surface border border-border rounded-xl p-4 h-[140px] flex flex-col justify-between relative transition-colors duration-[120ms] group hover:bg-[#17161F] hover:border-[#2A2838]">
              <div class="flex justify-between items-start">
                <span class="text-sm text-text-primary font-medium"><%= mask(@obfuscated, device.hostname) %></span>
                <div class="flex gap-1">
                  <button phx-click="modal_open" phx-value-modal_title={"Manage tags for #{device.hostname}"} phx-value-modal_description={if device_tags != [], do: "Current tags: #{Enum.join(device_tags, ", ")}", else: "No tags yet"} phx-value-modal_body={
                    Jason.encode!(%{"type" => "schema", "data" => Tunneld.Schema.data(:device_tag, %{hostname: device.hostname}), "default_values" => %{"mac" => device.mac}, "action" => "add_device_tag"})
                  } class="cursor-pointer">
                    <.tag size={14} class={if device_tags != [], do: "text-blue-400", else: "text-gray-2"} />
                  </button>
                </div>
              </div>

              <div :if={device_tags != []} class="flex gap-1 flex-wrap">
                <%= for tag <- Enum.take(device_tags, 3) do %>
                  <span class="bg-accent/10 text-accent px-1.5 py-0.5 rounded text-[10px] font-mono"><%= tag %></span>
                <% end %>
              </div>
              <div :if={device_tags == []} class="grow" />

              <div>
                <div class="font-mono text-sm text-text-primary"><%= mask(@obfuscated, device.ip) %></div>
                <div class="font-mono text-xs text-text-tertiary mt-0.5"><%= mask(@obfuscated, device.mac) %></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp mask(true, _value), do: "••••••••"
  defp mask(_, value), do: value
end

defmodule TunneldWeb.Live.NetworkDiagram do
  @moduledoc """
  LiveView for rendering an isometric network diagram with a unified sidebar
  that shows overlay details or various settings panels.
  """

  use TunneldWeb, :live_view

  # Dummy data for layout
  @sample_data %{
    gateway: %{id: "gw1"},
    services: [
      %{id: "svc1", type: :dnsmasq},
      %{id: "svc2", type: :dnscrypt},
      %{id: "svc3", type: :dhcpcd}
    ],
    devices: [
      %{id: "dev-1", type: :device, artifacts: [%{id: "dev0_app1"}, %{id: "dev0_app2"}]},
      %{id: "dev0", type: :device, artifacts: [%{id: "dev0_app1"}]}
    ]
  }

  # Tile and layout constants
  @tile_w 64
  @tile_h 32
  @horizontal_spacing 1
  @vertical_spacing 1
  @padding 3

  @impl true
  @doc """
  Mounts the LiveView, computes initial grid layout, and assigns
  tile dimensions, grid sizes, overlays JSON, and sidebar state.
  """
  def mount(_params, _session, socket) do
    layout = build_grid(@sample_data)

    socket =
      assign(socket,
        tile_w: @tile_w,
        tile_h: @tile_h,
        cols: layout.cols,
        rows: layout.rows,
        overlays: Jason.encode!(layout.overlays),
        selected_overlay: nil,
        active_panel: nil
      )

    {:ok, socket}
  end

  @impl true
  @doc """
  Handles click events on an overlay cell. Opens sidebar in
  `:overlay` mode with the clicked cell’s metadata.
  """
  def handle_event(
        "overlay_selected",
        %{"i" => i, "j" => j, "kind" => kind, "label" => label},
        socket
      ) do
    data = %{i: i, j: j, kind: kind, label: label}
    {:noreply, assign(socket, selected_overlay: data, active_panel: :overlay)}
  end

  @doc """
  Handles click on the close (✕) button in the sidebar; closes
  any open panel or overlay details.
  """
  def handle_event("close_sidebar", _params, socket) do
    {:noreply, assign(socket, selected_overlay: nil, active_panel: nil)}
  end

  @doc """
  Open the Encryption Settings panel.
  """
  def handle_event("open_encryption_settings", _params, socket),
    do: {:noreply, assign(socket, active_panel: :encryption, selected_overlay: nil)}

  @doc """
  Open the Notification Settings panel.
  """
  def handle_event("open_notification_settings", _params, socket),
    do: {:noreply, assign(socket, active_panel: :notifications, selected_overlay: nil)}

  @doc """
  Open the Internet Settings panel.
  """
  def handle_event("open_internet_settings", _params, socket),
    do: {:noreply, assign(socket, active_panel: :internet, selected_overlay: nil)}

  @doc """
  Open the Terminal panel.
  """
  def handle_event("open_terminal", _params, socket),
    do: {:noreply, assign(socket, active_panel: :terminal, selected_overlay: nil)}

  @impl true
  @doc """
  Renders the LiveView. It includes:
    - A top bar with four settings buttons.
    - The isometric canvas with a loader.
    - A unified sidebar that displays either overlay details or
      one of the settings panels, based on `@active_panel`.
  """
  def render(assigns) do
    ~H"""
    <div class="relative w-screen h-screen overflow-hidden">
      <!-- Top bar -->
      <div class="absolute top-0 left-0 right-0 z-10 flex space-x-2 p-2 bg-[#1b1b27] border-b-8 border-[#65659c]">
        <button
          phx-click="open_encryption_settings"
          class="px-3 py-1 bg-[#28283d] hover:bg-[#3a3a5c] text-[#e0e0ff] font-['Press_Start_2P'] text-[10px] uppercase tracking-widest"
        >
          Encryption Settings
        </button>
        <button
          phx-click="open_notification_settings"
          class="px-3 py-1 bg-[#28283d] hover:bg-[#3a3a5c] text-[#e0e0ff] font-['Press_Start_2P'] text-[10px] uppercase tracking-widest"
        >
          Notification Settings
        </button>
        <button
          phx-click="open_internet_settings"
          class="px-3 py-1 bg-[#28283d] hover:bg-[#3a3a5c] text-[#e0e0ff] font-['Press_Start_2P'] text-[10px] uppercase tracking-widest"
        >
          Internet Settings
        </button>
        <button
          phx-click="open_terminal"
          class="px-3 py-1 bg-[#28283d] hover:bg-[#3a3a5c] text-[#e0e0ff] font-['Press_Start_2P'] text-[10px] uppercase tracking-widest"
        >
          Terminal
        </button>
      </div>
      <!-- Isometric canvas & loader -->
      <div
        id="iso-grid"
        phx-hook="IsoGrid"
        phx-update="ignore"
        data-tile-w={@tile_w}
        data-tile-h={@tile_h}
        data-cols={@cols}
        data-rows={@rows}
        data-overlays={@overlays}
        class="absolute inset-0 w-full h-full pt-10 bg-[#15151d]"
      >
        <div
          id="iso-loader"
          class="absolute inset-0 flex items-center justify-center bg-[#15151d] text-white font-mono text-xs tracking-widest z-50 select-none"
        >
          LOADING…
        </div>
        <canvas class="block w-full h-full"></canvas>
      </div>
      <!-- Unified sidebar -->
      <%= if @active_panel do %>
        <div class="absolute top-0 right-0 h-screen md:w-[400px] lg:w-[600px] w-full bg-[#1b1b27] border-l-8 border-[#65659c] p-6 flex flex-col text-[#e0e0ff] font-['Press_Start_2P',monospace] text-[11px] leading-snug select-none z-30">
          <div class="flex items-center justify-between mb-6">
            <span class="uppercase tracking-widest">
              <%= case @active_panel do %>
                <% :overlay -> %>
                  DETAILS
                <% :encryption -> %>
                  ENCRYPTION SETTINGS
                <% :notifications -> %>
                  NOTIFICATION SETTINGS
                <% :internet -> %>
                  INTERNET SETTINGS
                <% :terminal -> %>
                  TERMINAL
              <% end %>
            </span>
            <button
              phx-click="close_sidebar"
              class="text-[#e0e0ff] hover:text-[#9fa1ff] focus:outline-none text-lg leading-none"
            >
              ✕
            </button>
          </div>
          <div class="border-t border-dashed border-[#65659c] mb-6"></div>

          <%= case @active_panel do %>
            <% :overlay -> %>
              <div class="space-y-3">
                <p><span class="text-[#9fa1ff]">Kind:</span> <%= @selected_overlay.kind %></p>
                <p><span class="text-[#9fa1ff]">ID:</span> <%= @selected_overlay.label %></p>
                <p>
                  <span class="text-[#9fa1ff]">Coords:</span>
                  (<%= @selected_overlay.i %>, <%= @selected_overlay.j %>)
                </p>
              </div>
            <% :encryption -> %>
              <p>🔒 Configure your encryption keys, ciphers, and TLS settings here.</p>
            <% :notifications -> %>
              <p>🔔 Choose which alerts you’d like to receive and how.</p>
            <% :internet -> %>
              <p>🌐 Set upstream/router preferences, DNS, and bandwidth limits.</p>
            <% :terminal -> %>
              <p>💻 Launch an embedded terminal session or SSH settings.</p>
          <% end %>

          <div class="flex-grow"></div>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Builds the grid layout for gateway, services, devices, and artifacts:

    - Places gateway at center top.
    - Renders services in a horizontal row.
    - Arranges devices in an NxN grid beneath.
    - Stacks artifacts below each device.
  """
  defp build_grid(%{gateway: gateway, services: services, devices: devices}) do
    device_count = length(devices)
    services_count = length(services)

    max_artifacts =
      devices
      |> Enum.map(&length(&1.artifacts || []))
      |> Enum.max(fn -> 0 end)

    cols =
      max(services_count * 2, device_count * 2 - 1)
      |> Kernel.+(@padding * 2)

    services_check = if(services_count > 0, do: 4, else: 1)
    devices_check = if(device_count > 0, do: 2, else: 3)
    artifact_check = if(max_artifacts > 0, do: @padding * 2 + 1, else: 2)

    rows =
      1 +
        services_check +
        devices_check +
        max_artifacts * 2 +
        artifact_check

    center_x = div(cols, 2)
    gateway_y = @padding
    service_y = gateway_y + 3
    device_y = service_y + 3

    gateway_overlay = [%{i: center_x, j: gateway_y, kind: "gateway", label: gateway.id}]
    services_overlay = build_services(services, center_x, service_y)
    {devices_overlay, _} = build_devices(devices, center_x, device_y)

    %{rows: rows, cols: cols, overlays: gateway_overlay ++ services_overlay ++ devices_overlay}
  end

  @doc """
  Places service icons in a row centered around the X axis.
  """
  defp build_services(services, center_x, y) do
    Enum.with_index(services, fn %{id: id, type: _}, idx ->
      %{
        i: center_x - length(services) + @horizontal_spacing + idx * 2,
        j: y,
        kind: "service",
        label: id
      }
    end)
  end

  @doc """
  Places devices in an NxN grid and stacks each device’s artifacts underneath.
  """
  defp build_devices(devices, x, y) do
    total_span = length(devices) * 2 - 1
    offset = div(total_span, 2)

    Enum.reduce(Enum.with_index(devices), {[], 0}, fn {device, idx}, {acc, max_art} ->
      i = x + idx * 2 - offset
      j = y

      dev = %{i: i, j: j, kind: "device", label: device.id}

      arts =
        Enum.with_index(device.artifacts, fn %{id: id}, k ->
          %{i: i, j: j + k * 2 + @vertical_spacing + 2, kind: "artifact", label: id}
        end)

      {[dev | arts] ++ acc, max(max_art, length(arts))}
    end)
  end
end

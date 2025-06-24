defmodule TunneldWeb.Live.IsoGrid do
  @moduledoc """
  Isometric page - this will be the start to the renderer
  """
  use TunneldWeb, :live_view

  # Dummy data
  @sample_data %{
    gateway: %{id: "gw1"},
    services: [
      %{id: "svc1", type: :dnsmasq},
      %{id: "svc2", type: :dnscrypt},
      %{id: "svc3", type: :dhcpcd}
    ],
    devices: [
      %{
        id: "dev0",
        type: :device,
        artifacts: []
      },
      # %{
      #   id: "dev0",
      #   type: :device,
      #   artifacts: [%{id: "dev0_app1"}, %{id: "dev0_app2"}]
      # },
      # %{
      #   id: "dev0",
      #   type: :device,
      #   artifacts: [%{id: "dev0_app1"}, %{id: "dev0_app2"}]
      # },
      # %{
      #   id: "dev0",
      #   type: :device,
      #   artifacts: [%{id: "dev0_app1"}, %{id: "dev0_app2"}]
      # },
      # %{
      #   id: "dev0",
      #   type: :device,
      #   artifacts: [
      #     %{id: "dev0_app1"},
      #     %{id: "dev0_app2"},
      #     %{id: "dev0_app1"},
      #     %{id: "dev0_app2"},
      #     %{id: "dev0_app1"},
      #     %{id: "dev0_app2"},
      #     %{id: "dev0_app1"},
      #     %{id: "dev0_app1"},
      #     %{id: "dev0_app2"}
      #   ]
      # }
    ]
  }

  # Constants
  @tile_w 64
  @tile_h 32
  @horizontal_spacing 3
  @vertical_spacing 3
  @padding 4

  @doc """
  Mounts the LiveView and assigns the calculated layout grid
  """
  def mount(_params, _session, socket) do
    layout = build_grid(@sample_data)

    socket =
      assign(socket,
        tile_w: @tile_w,
        tile_h: @tile_h,
        cols: layout.cols,
        rows: layout.rows,
        overlays: Jason.encode!(layout.overlays)
      )

    {:ok, socket}
  end

  @doc """
  Render the init data and the canvas
  """
  def render(assigns) do
    ~H"""
    <div
      id="iso-grid"
      phx-hook="IsoGrid"
      data-tile-w={@tile_w}
      data-tile-h={@tile_h}
      data-cols={@cols}
      data-rows={@rows}
      data-overlays={@overlays}
      style="
        position: absolute;
        top: 0; left: 0;
        width: 100vw;
        height: 100vh;
        overflow: hidden;
        background: #15151d;
      "
    >
      <canvas style="
        display: block;
        width: 100%;
        height: 100%;
      "></canvas>
    </div>
    """
  end

  @doc """
  Builds the complete layout grid:
  - Gateway at top center
  - Services in a row beneath
  - Devices in a NxN grid beneath that
  - Artifacts below each device
  """
  def build_grid(%{gateway: gateway, services: services, devices: devices}) do
    device_count = length(devices)

    max_artifact_depth =
      devices
      |> Enum.map(fn d -> length(d.artifacts || []) end)
      |> Enum.max(fn -> 0 end)

    cols = device_count * @horizontal_spacing + @padding * 2
    # gateway + spacing + service
    base_y = @padding + 3 + 1
    rows = base_y + max_artifact_depth + @padding

    center_x = div(cols, 2)
    gateway_y = @padding - 2
    service_y = gateway_y + 3
    device_y = service_y + 3

    gateway_overlay = [%{i: center_x, j: gateway_y, kind: "gateway", label: gateway.id}]
    services_overlay = build_services(services, center_x, service_y)
    {devices_overlay, _} = build_devices(devices, device_y)

    %{
      rows: rows,
      cols: cols,
      overlays: gateway_overlay ++ services_overlay ++ devices_overlay
    }
  end

  @doc """
  Places services in a row, centered around center_x
  """
  defp build_services(services, center_x, y) do
    count = length(services)
    start_x = center_x - count

    Enum.with_index(services, fn %{id: id, type: type}, idx ->
      %{
        i: (start_x + 1) + idx * 2,
        j: y,
        kind: "service",
        label: id,
        type: Atom.to_string(type)
      }
    end)
  end

  @doc """
  Places devices in an NxN grid, with artifacts stacked below each device
  """
  defp build_devices(devices, y) do
    Enum.reduce(Enum.with_index(devices), {[], 0}, fn {device, idx}, {acc, max_artifacts} ->
      i = 1 + @padding + idx * @horizontal_spacing
      j = y

      device_overlay = %{i: i, j: j, kind: "device", label: device.id}

      artifacts =
        Enum.with_index(device.artifacts, fn %{id: id}, ai ->
          %{i: i, j: j + @vertical_spacing + ai, kind: "artifact", label: id}
        end)

      {acc ++ [device_overlay | artifacts], max(max_artifacts, length(artifacts))}
    end)
  end
end

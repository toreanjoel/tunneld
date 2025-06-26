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
      # %{
      #   id: "dev-1",
      #   type: :device,
      #   artifacts: [
      #     %{id: "dev0_app1"},
      #     %{id: "dev0_app2"},
      #     %{id: "dev0_app1"},
      #     %{id: "dev0_app2"}
      #   ]
      # },
      %{
        id: "dev0",
        type: :device,
        artifacts: [%{id: "dev0_app1"}]
      },
      # %{
      #   id: "dev0",
      #   type: :device,
      #   artifacts: [%{id: "dev0_app1"}]
      # },
      # %{
      #   id: "dev0",
      #   type: :device,
      #   artifacts: [%{id: "dev0_app1"}]
      # },
      # %{
      #   id: "dev0",
      #   type: :device,
      #   artifacts: [%{id: "dev0_app1"}]
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
      #     %{id: "dev0_app1"},
      #     %{id: "dev0_app2"}
      #   ]
      # },
      # %{
      #   id: "dev0",
      #   type: :device,
      #   artifacts: [%{id: "dev0_app1"}, %{id: "dev0_app2"}]
      # }
    ]
  }

  # Constants
  @tile_w 128
  @tile_h 64
  @horizontal_spacing 1
  @vertical_spacing 1
  @padding 3

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
    services_count = length(services)

    # We need this so we can account for how many there will be
    max_artifact_depth =
      devices
      |> Enum.map(fn d -> length(d.artifacts || []) end)
      |> Enum.max(fn -> 0 end)

    # We add the general padding along with the spacing in the relevant axis
    cols = max(services_count * 2, device_count * 2 - 1) + @padding * 2

    # We add dynamic spacers vertically based on the existence so have a even grid if the sectino doesnt exist
    services_check = if services_count > 0, do: 3 + 1, else: 1
    devices_check = if device_count > 0, do: 1 + 1, else: 3
    artifact_check = if max_artifact_depth > 0, do: @padding * 2 + 1, else: 2
    rows =
        1 +  # gateway
        services_check + # service spacer + services
        devices_check + # device spacer + devices
        (max_artifact_depth + max_artifact_depth) + # deepest artifacts + make sure to account for spaces between as we do a n + n
        artifact_check

    # Get the center of the grid
    center_x = div(cols, 2)

    # The gateway Y position as a variable that we can reference to start placing others from
    gateway_y = @padding
    # The starting point of servcices on the vertical axis realtive to gateway
    service_y = gateway_y + 3
    # The starting point of devices on the vertical axis realtive to services
    device_y = service_y + 3

    # Render the Gateway Icon
    gateway_overlay = [%{i: center_x, j: gateway_y, kind: "gateway", label: gateway.id}]

    # Render services Icons
    services_overlay = build_services(services, center_x, service_y)

    # Render the Devices Icons and their Artifacts
    {devices_overlay, _} = build_devices(devices, center_x, device_y)

    # The data structure that will be used to render for the client
    %{
      rows: rows,
      cols: cols,
      overlays: gateway_overlay ++ services_overlay ++ devices_overlay
    }
  end

  @doc """
  Places services in a row, centered around center_x
  """
  def build_services(services, center_x, y) do
    count = length(services)
    start_x = center_x - count

    Enum.with_index(services, fn %{id: id, type: type}, idx ->
      %{
        # Services are non dynamic
        # relative from gateway, center and horizontally 1 plus n+N
        i: start_x + @horizontal_spacing + idx + idx,
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
  def build_devices(devices, x, y) do
    total_span = length(devices) * 2 - 1
    offset = div(total_span, 2)

    Enum.reduce(Enum.with_index(devices), {[], 0}, fn {device, idx}, {acc, max_artifacts} ->
      # relative to passed value - services is passed as x with padding
      # postion horizontally with n + n to add a spacer
      # take full horizonta area with spaces and calculate half to center horizontally
      i = x + (idx + idx) - offset
      j = y

      device_overlay = %{i: i, j: j, kind: "device", label: device.id}

      # Render the artifacts relative to the device associated with it
      # Make sure we are 2 vertical spaces away from device
      # We do a n+n for spacing to add padding between artifacts
      artifacts =
        Enum.with_index(device.artifacts, fn %{id: id}, idx ->
          %{i: i, j: j + (idx + idx) + @vertical_spacing + 2, kind: "artifact", label: id}
        end)

      {acc ++ [device_overlay | artifacts], max(max_artifacts, length(artifacts))}
    end)
  end
end

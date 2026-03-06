defmodule TunneldWeb.Live.Dashboard.NetworkGraph do
  @moduledoc """
  Builds the isometric network topology graph data for the dashboard's
  Network Map view.

  Generates node and link structures representing the internet uplink,
  gateway, and connected devices for rendering on an HTML canvas.
  """

  @doc """
  Build the full network graph data structure from current state.
  """
  def build(internet?, devices) do
    device_list = devices || []
    uplink_state = if internet?, do: "enabled", else: "disabled"

    base_nodes = [
      %{
        id: "internet",
        label: "Internet",
        type: "cloud",
        pos: %{x: 0, y: -4, z: 0.2},
        size: 1,
        color: "#9afbff",
        icon: %{variant: "cloud", state: "enabled"}
      },
      %{
        id: "uplink",
        label: "WiFi",
        type: "router",
        pos: %{x: 0, y: -1.6, z: 0.2},
        size: 1,
        color: "#e69df9",
        icon: %{variant: "router", state: uplink_state}
      },
      %{
        id: "gateway",
        label: "Tunneld",
        type: "router",
        pos: %{x: 0, y: 0, z: 0.2},
        size: 1,
        color: "#a6b5fd",
        icon: %{variant: "switch", state: "enabled"}
      }
    ]

    device_nodes =
      device_list
      |> Enum.sort_by(&device_sort_key/1)
      |> Enum.with_index()
      |> Enum.map(fn {device, idx} ->
        %{
          id: "device-#{idx}",
          label: device_label(device, idx),
          type: "device",
          pos: device_position(idx),
          size: 1,
          color: "#7bfee0",
          icon: %{variant: "device", state: "enabled"},
          meta: device_meta(device)
        }
      end)

    base_links =
      if internet? do
        [
          %{id: "internet-uplink", from: "internet", to: "uplink", activity: 1},
          %{id: "uplink-gateway", from: "uplink", to: "gateway", activity: 0.8}
        ]
      else
        []
      end

    device_links =
      Enum.map(device_nodes, fn device ->
        %{id: "gateway-#{device.id}", from: "gateway", to: device.id, activity: 0.4}
      end)

    %{
      nodes: base_nodes ++ device_nodes,
      links: base_links ++ device_links,
      nodeSettings: %{
        default: [
          %{label: "Status", value: if(internet?, do: "Online", else: "Offline")},
          %{label: "Policy", value: "Standard"}
        ]
      },
      nodeServices: %{
        default: [
          %{name: "Edge agent", desc: "Standard policy services", status: "online"}
        ]
      }
    }
  end

  defp device_position(index) do
    per_row = 4
    row = div(index, per_row)
    col = rem(index, per_row)

    anchor_x = 3.2
    anchor_y = 1.8
    x_step = 2.05
    y_step = 3.05

    x = anchor_x - col * x_step - row * 1.45
    y = anchor_y + row * y_step

    %{x: Float.round(x, 2), y: Float.round(y, 2), z: 0.2}
  end

  defp device_label(device, index) do
    Map.get(device, :hostname) ||
      Map.get(device, "hostname") ||
      Map.get(device, :ip) ||
      Map.get(device, "ip") ||
      "Device #{index + 1}"
  end

  defp device_sort_key(device) do
    (Map.get(device, :hostname) || Map.get(device, "hostname") || "") <>
      (Map.get(device, :mac) || Map.get(device, "mac") || "") <>
      (Map.get(device, :ip) || Map.get(device, "ip") || "")
  end

  defp device_meta(device) do
    %{
      ip: Map.get(device, :ip) || Map.get(device, "ip"),
      mac: Map.get(device, :mac) || Map.get(device, "mac")
    }
  end
end

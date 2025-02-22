defmodule SentinelWeb.Live.Components.Nodes do
  @moduledoc """
  Nodes that are available and connected as devices to the system.
  """
  use SentinelWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:nodes")
    end
    {:ok, socket}
  end

  def update(assigns, socket) do
    # Example list of nodes, each with a type and a status.
    socket =
      socket
      |> assign(
        nodes: [
          %{id: "id1", type: "cpu", status: "active"},
          %{id: "id2", type: "storage", status: "warning"},
          %{id: "id3", type: "vpn", status: "active"},
          %{id: "id4", type: "pc", status: "offline"}
        ]
      )
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the nodes.
  """
  def render(assigns) do
    ~H"""
    <div class="p-5">
      <div class="mb-5">
        <div class="text-xl text-gray-1 font-medium">Nodes</div>
        <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
      </div>
      <div class="flex flex-wrap gap-3 items-center justify-start">
        <%= for node <- @nodes do %>
          <div phx-click="show_details" phx-value-type={"node"} phx-value-id={node.id} class="relative w-[120px] md:w-[75px] h-[120px] md:h-[75px] p-2 bg-secondary flex items-center justify-center rounded-md hover:bg-secondary cursor-pointer">
            <.icon class="w-10 h-10" name={get_icon(node.type)} />
            <div class={"absolute bottom-[5px] right-2 w-[10px] h-[10px] rounded-full " <> get_status_color(node.status)}>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper function to select the icon based on node type.
  defp get_icon("vpn"), do: "hero-shield-check"
  defp get_icon("storage"), do: "hero-circle-stack"
  defp get_icon("cpu"), do: "hero-cpu-chip"
  defp get_icon("pc"), do: "hero-computer-desktop"
  defp get_icon(_), do: "hero-question-mark-circle"

  # Helper function to set a status indicator color based on node status.
  defp get_status_color("active"), do: "bg-green"
  defp get_status_color("warning"), do: "bg-yellow"
  defp get_status_color("offline"), do: "bg-red"
  defp get_status_color(_), do: "bg-gray-500"
end

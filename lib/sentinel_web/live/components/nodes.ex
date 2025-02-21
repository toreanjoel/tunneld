defmodule SentinelWeb.Live.Components.Nodes do
  @moduledoc """
  Nodes that are available and connected as devices to the system.
  """
  use SentinelWeb, :live_component

  def update(_, socket) do
    # Example list of nodes, each with a type and a status.
    socket =
      socket
      |> assign(nodes: [
        %{type: "cpu", status: "active"},
        %{type: "storage", status: "warning"},
        %{type: "vpn", status: "active"},
        %{type: "pc", status: "offline"}
      ])

    {:ok, socket}
  end

  @doc """
  Render the nodes.
  """
  def render(assigns) do
    ~H"""
    <div class="p-5">
      <div class="mb-8 text-2xl text-gray-1 font-medium">Nodes</div>
      <div class="flex flex-wrap gap-1 items-center justify-start">
        <%= for node <- @nodes do %>
          <div class="border-2 border-secondary relative w-[120px] md:w-[75px]  h-[120px] md:h-[75px]  p-2 bg-primary flex items-center justify-center rounded-md hover:bg-secondary cursor-pointer">
            <.icon class="w-10 h-10" name={get_icon(node.type)} />
            <div class={"absolute bottom-[5px] right-2 w-[10px] h-[10px] rounded-full " <> get_status_color(node.status)}></div>
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

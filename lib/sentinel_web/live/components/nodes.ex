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
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the nodes.
  """
  def render(assigns) do
    assigns = assigns
    |> assign(nodes: assigns.data)

    ~H"""
    <div class="p-5">
      <div class="mb-5 flex flex-row">
        <div class="flex-1">
          <div class="text-xl text-gray-1 font-medium">Nodes</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Add a Node"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Sentinel.Schema.Node.data(:add),
              "default_values" => %{},
              "action" => "add_node"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md text-gray-1"
        >
          <.icon class="w-6 h-6" name="hero-cpu-chip" />
          <div class="truncate text-xs">Add Node</div>
        </div>
      </div>
      <div class="flex flex-wrap gap-3 items-center justify-start">
        <div :if={Enum.empty?(@nodes)} class="w-[100px] md:w-[60px] h-[100px] md:h-[60px] bg-secondary flex items-center justify-center rounded-md opacity-10">
          <.icon class="w-8 h-8 text-white" name="hero-cpu-chip" />
        </div>

          <%= if !Enum.empty?(@nodes) do %>
            <%= for node <- @nodes do %>
              <div
                phx-click="show_details"
                phx-value-type="node"
                phx-value-id={node.id || node["id"]}
                class="relative w-[100px] md:w-[60px] h-[100px] md:h-[60px] p-2 bg-secondary flex items-center justify-center rounded-md hover:bg-secondary cursor-pointer"
              >
                <.icon class="w-8 h-8" name={node.icon || "hero-question-mark-circle"} />
                <div class={"absolute bottom-[5px] right-2 w-[6px] h-[6px] rounded-full " <> get_status_color(node.status || false)}>
                </div>
              </div>
            <% end %>
          <% end %>
      </div>
    </div>
    """
  end

  # Helper function to set a status indicator color based on node status.
  defp get_status_color(true), do: "bg-green"
  defp get_status_color(_), do: "bg-red"
end

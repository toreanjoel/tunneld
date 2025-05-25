defmodule SentinelWeb.Live.Components.Instances do
  @moduledoc """
  Instances that are available and connected as devices to the system.
  """
  use SentinelWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:instances")
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    # Example list of instances, each with a type and a status.
    socket =
      socket
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the instances.
  """
  def render(assigns) do
    assigns =
      assigns
      |> assign(instances: assigns.data)

    ~H"""
    <div class="p-5">
      <div class="mb-5 flex flex-row">
        <div class="flex-1">
          <div class="text-xl text-gray-1 font-medium">Intstances</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Add an Instance"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Sentinel.Schema.Instance.data(:add),
              "default_values" => %{
                # These below needs to be more dynamic but this is supported given what we render at the moment
                "icon" => ["vpn", "storage", "cpu", "pc", "other"]
              },
              "action" => "add_instance"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md text-gray-1"
        >
          <.icon class="w-6 h-6" name={get_icon("cpu")} />
          <div class="truncate text-xs">Add Instance</div>
        </div>
      </div>

      <div>
        <div
          :if={Enum.empty?(@instances)}
          class="w-[100px] md:w-[60px] h-[100px] md:h-[60px] bg-secondary flex items-center justify-center rounded-md opacity-10"
        >
          <.icon class="w-8 h-8 text-white" name="hero-cpu-chip" />
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <%= if !Enum.empty?(@instances) do %>
            <%= for instance <- @instances do %>
              <div
                phx-click="show_details"
                phx-value-type="instance"
                phx-value-id={instance.id || instance["id"]}
                class="p-4 flex flex-col bg-secondary rounded-lg w-full h-[80px] cursor-pointer"
                style="animation: fadeIn 0.5s ease-out forwards;"
              >
                <div class="flex flex-row items-center">
                  <div class="grow">
                    <div class="text-lg bold truncate"><%= instance.name %></div>
                  </div>
                  <div class={"w-3 h-3 rounded-full " <> get_status_color(instance.status || false)} />
                </div>
                <div class="grow py-2" />
                <div class="text-sm truncate"><%= instance.port %></div>
                <div class="text-sm truncate">
                  <a
                    :if={not Enum.empty?(instance.tunnel)}
                    href={"https://" <> instance.tunnel["subdomain"]}
                    class="flex flex-row items-center justify-center"
                    target="_blank"
                  >
                    <div class="grow">
                      <%= instance.tunnel["subdomain"] %>
                    </div>
                    <.icon class="w-[18px] h-[18px]" name="hero-arrow-top-right-on-square" />
                  </a>
                  <span :if={Enum.empty?(instance.tunnel)}>Not Connected</span>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper function to select the icon based on instance type.
  defp get_icon("vpn"), do: "hero-shield-check"
  defp get_icon("storage"), do: "hero-circle-stack"
  defp get_icon("cpu"), do: "hero-cpu-chip"
  defp get_icon("pc"), do: "hero-computer-desktop"
  defp get_icon("key"), do: "hero-key"
  defp get_icon(_), do: "hero-question-mark-circle"

  # Helper function to set a status indicator color based on instance status.
  defp get_status_color(true), do: "bg-green"
  defp get_status_color(_), do: "bg-red"
end

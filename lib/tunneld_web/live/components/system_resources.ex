defmodule TunneldWeb.Live.Components.SystemResources do
  @moduledoc """
  SystemResources of the devices and available resources

  Example of how the data will be sent but will be sent with real data using os_mon

    data = %{
      resources: %{
        cpu: Enum.random(1..100),
        mem: Enum.random(1..100),
        storage: Enum.random(1..100),
        temp: 45.2
      }
    }

    id = "resources"
    module = SystemResources


    Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:resources", %{id: id, module: module, data: data})
  """
  use TunneldWeb, :live_component

  # The constant for the gauge radius
  @radius 65

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:system_resources")
    end
    {:ok, socket}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the resource usage as gauges.
  """
  def render(assigns) do
    data = Map.get(assigns, :data)
    resources = Map.get(data, :resources, %{
      cpu: 0,
      mem: 0,
      storage: 0,
      temp: nil
    })

    # Calculate the circumference for the progress circles
    assigns =
      assigns
      |> assign(resources: resources)
      |> assign(radius: @radius)
      |> assign(circumference: 2 * :math.pi() * @radius)

    ~H"""
    <div class="p-3 md:p-5">
      <div class="mb-4 md:mb-5 flex flex-col">
        <div class="text-lg md:text-xl text-gray-1 font-medium">System Resources</div>
        <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
      </div>

      <div class="flex items-center justify-center">
        <div class="grid grid-cols-2 gap-2">
          <%= for {label, percent, available?} <- gauges(@resources) do %>
            <div class={"bg-primary relative w-full max-w-[150px] md:max-w-[180px] rounded-lg #{if not available?, do: "opacity-30 pointer-events-none", else: ""}"}>
              <svg class="w-full h-full" viewBox="0 0 170 170">
                <!-- Background circle -->
                <circle
                  cx="85"
                  cy="85"
                  r={@radius}
                  stroke-width="5"
                  fill="none"
                />
                <!-- Progress circle -->
                <circle
                  cx="85"
                  cy="85"
                  r={@radius}
                  class={if available?, do: get_percent_color(percent) <> " animate-dashoffset", else: ""}
                  stroke-width="10"
                  fill="#202226"
                  stroke-dasharray={@circumference}
                  stroke-dashoffset={if available?, do: @circumference * (1 - percent / 100), else: @circumference}
                  stroke-linecap="round"
                  style="transform: rotate(-90deg); transform-origin: center;"
                  stroke="currentColor"
                />
              </svg>
              <!-- Percentage and label -->
              <div class="absolute inset-0 flex flex-col items-center justify-center text-xs sm:text-sm text-white">
                <%= if available?, do: "#{percent}%", else: "—" %>
                <div class="text-[10px]"><%= label %></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp gauges(resources) do
    cpu = Map.get(resources, :cpu)
    mem = Map.get(resources, :mem)
    storage = Map.get(resources, :storage)
    temp = Map.get(resources, :temp)

    # Convert temp (°C) to a percentage for the gauge (0-100°C range)
    temp_percent = if temp, do: min(round(temp), 100), else: nil

    [
      {"CPU", cpu || 0, not is_nil(cpu)},
      {"MEM", mem || 0, not is_nil(mem)},
      {"STORAGE", storage || 0, not is_nil(storage)},
      {"TEMP", temp_percent || 0, not is_nil(temp)}
    ]
  end

  # Check the percent and return relevant color
  defp get_percent_color(val) do
    cond do
      val > 60 and val <= 80 -> "text-yellow"
      val > 80 -> "text-red"
      true -> "text-green"
    end
  end
end
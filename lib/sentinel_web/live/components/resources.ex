defmodule SentinelWeb.Live.Components.Resources do
  @moduledoc """
  Resources of the devices and available resources
  """
  use SentinelWeb, :live_component

  # The constant for the gauge radius
  @radius 65

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:resources")
    end
    {:ok, socket}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(
        resources: %{
          cpu: Enum.random(1..100),
          mem: Enum.random(1..100),
          storage: Enum.random(1..100)
        }
      )
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the resource usage as gauges.
  """
  def render(assigns) do
    # Calculate the circumference for the progress circles
    assigns =
      assigns
      |> assign(radius: @radius)
      |> assign(circumference: 2 * :math.pi() * @radius)

    ~H"""
    <div class="p-5">
      <div class="mb-5 flex flex-col">
        <div class="text-xl text-gray-1 font-medium">Resources</div>
        <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
      </div>

      <div class="flex items-center justify-center">
        <!-- 1 col on small screens, 2 on md, 3 on lg -->
        <div class="grid grid-cols-2 md:grid-cols-2 xl:grid-cols-3 gap-2">
          <%= for {resource, percent} <- @resources do %>
            <!-- On small screens: full width; on md and above, limit width -->
            <div class="bg-primary relative w-full md:max-w-[200px] rounded-lg">
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
                  class={get_percent_color(percent)}
                  stroke-width="10"
                  fill="#202226"
                  stroke-dasharray={@circumference}
                  stroke-dashoffset={@circumference * (1 - percent / 100)}
                  stroke-linecap="round"
                  style="transform: rotate(-90deg); transform-origin: center;"
                  stroke="currentColor"
                />
              </svg>
              <!-- Percentage and label -->
              <div class="absolute inset-0 flex flex-col items-center justify-center text-3xl md:text-lg text-white">
                <%= "#{percent}%" %>
                <div class="text-xl md:text-xs"><%= String.upcase(to_string(resource)) %></div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Check the percent and return relevant color
  defp get_percent_color(val) do
    cond do
      val > 50 and val <= 70 -> "text-yellow"
      val > 70 -> "text-red"
      true -> "text-green"
    end
  end
end

defmodule SentinelWeb.Live.Components.Services do
  @moduledoc """
  Running Services on the operating system and their availability
  """
  use SentinelWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:services")
    end
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(data: Map.get(assigns, :data, %{}))}
  end

  @doc """
  Render the services and their status
  """
  def render(assigns) do
    data = Map.get(assigns, :data)
    status = Map.get(data, :status, %{})

    assigns =
      assigns
      |> assign(status: status)
      |> assign(loading: Enum.empty?(status))

    ~H"""
    <div class="p-5">
      <div class="mb-5">
        <div class="text-xl text-gray-1 font-medium">Services</div>
        <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
      </div>

      <div :if={@loading} class="grid grid-cols-2 xl:grid-cols-3 gap-2">
        <div class="flex flex-row gap-3 py-2 px-3 items-center rounded-md bg-secondary opacity-20">
          <div class="text-sm truncate text-gray-1">Checking Services</div>
        </div>
      </div>

      <div :if={!@loading} class="grid grid-cols-2 xl:grid-cols-3 gap-2">
        <%= for {service, status} <- @status do %>
          <div phx-click="show_details" phx-value-type="service" phx-value-id={service} class="bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer">
            <div class={"w-[13px] h-[13px] rounded-full #{status(status)}"}></div>
            <div class="text-sm truncate"><%= service %></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # The status of the services on the operating system
  defp status(service) when service === true, do: "bg-green"
  defp status(_), do: "bg-red"
end

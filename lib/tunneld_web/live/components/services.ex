defmodule TunneldWeb.Live.Components.Services do
  @moduledoc """
  Running Services on the operating system and their availability
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:services")
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    obfuscated = Map.get(assigns, :obfuscated, false)

    socket =
      socket
      |> assign_new(:obfuscated, fn -> false end)
      |> assign(data: Map.get(assigns, :data, %{}))
      |> assign(:obfuscated, obfuscated)

    {:ok, socket}
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
    <div class="p-3 md:p-5">
      <div class="mb-4 md:mb-5 flex flex-row">
        <div class="flex-1">
          <div class="text-lg md:text-xl text-gray-1 font-medium">Services</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
      </div>

      <div :if={@loading} class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-2">
        <div class="flex flex-row gap-3 py-2 px-3 items-center rounded-md bg-secondary opacity-20">
          <div class="text-sm truncate text-gray-1">Checking Services</div>
        </div>
      </div>

      <div :if={!@loading} class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-2">
        <%= for {service, service_status} <- @status do %>
          <div
            phx-click="show_details"
            phx-value-type="service"
            phx-value-id={service}
            class="bg-primary flex flex-row gap-3 py-2 px-3 items-center rounded-md hover:bg-secondary cursor-pointer"
          >
            <div class={"w-[13px] h-[13px] rounded-full #{status_class(service_status)}"}></div>
            <div class="text-sm truncate"><%= service %></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # The status of the services on the operating system
  defp status_class(true), do: "bg-green"
  defp status_class(_), do: "bg-red"
end

defmodule TunneldWeb.Live.Components.Shares do
  @moduledoc """
  Shares that are available and connected as devices to the system.
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:shares")
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    # Example list of shares, each with a type and a status.
    socket =
      socket
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the shares.
  """
  def render(assigns) do
    assigns =
      assigns
      |> assign(shares: assigns.data)

    ~H"""
    <div class="p-5">
      <div class="mb-5 flex flex-row">
        <div class="flex-1">
          <div class="text-xl text-gray-1 font-medium">Shares</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Add an Share"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Tunneld.Schema.Share.data(:add),
              "default_values" => %{},
              "action" => "add_share"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
        >
          <.icon class="w-6 h-6" name="hero-cpu-chip" />
          <div class="truncate text-xs">Add Share</div>
        </div>
      </div>

      <div>
        <div
          :if={Enum.empty?(@shares)}
          class="w-[100px] md:w-[60px] h-[100px] md:h-[60px] bg-secondary flex items-center justify-center rounded-md opacity-10"
        >
          <.icon class="w-8 h-8 text-white" name="hero-cpu-chip" />
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <%= if !Enum.empty?(@shares) do %>
            <%= for share <- @shares do %>
              <div
                phx-click="show_details"
                phx-value-type="share"
                phx-value-id={share.id || share["id"]}
                class="p-4 flex flex-col bg-secondary rounded-lg w-full h-[80px] cursor-pointer"
                style="animation: fadeIn 0.5s ease-out forwards;"
              >
                <div class="flex flex-row items-center">
                  <div class="grow">
                    <div class="text-lg bold truncate"><%= share.name %></div>
                  </div>
                  <div class={"w-3 h-3 rounded-full " <> get_status_color(share.status || false)} />
                </div>
                <div class="grow py-2" />
                <div class="text-sm truncate"><%= share.port %></div>
                <div class="text-sm truncate">
                 <%!-- TODO: add details on teh share here once exposed --%>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper function to set a status indicator color based on share status.
  defp get_status_color(true), do: "bg-green"
  defp get_status_color(_), do: "bg-red"
end

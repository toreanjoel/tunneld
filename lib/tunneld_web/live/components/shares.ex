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
          phx-value-modal_title="Add Private Share"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Tunneld.Schema.Share.data(:add_private),
              "default_values" => %{},
              "action" => "add_private_share"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
        >
          <.icon class="w-6 h-6" name="hero-cpu-chip" />
          <div class="truncate text-xs">Bind Private</div>
        </div>

        <div
          phx-click="modal_open"
          phx-value-modal_title="Add Share"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Tunneld.Schema.Share.data(:add_public),
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
              <% kind = share.kind || "host" %>
              <div
                phx-click="show_details"
                phx-value-type="share"
                phx-value-id={share.id || share["id"]}
                class="p-3 gap-2 flex flex-col rounded-lg w-full h-[80px] cursor-pointer bg-secondary transition-colors duration-150"
                style="animation: fadeIn 0.5s ease-out forwards;"
              >
                <div class="flex items-center gap-2 grow">
                  <.icon class="w-5 h-5 shrink-0" name={kind_icon(kind)} />
                  <div class="grow">
                    <div class="text-md font-semibold truncate"><%= share.name %></div>
                  </div>
                  <div class={["w-3 h-3 rounded-full", get_status_color(share.status || false)]} />
                </div>

                <div class="flex items-center justify-between text-xs flex-shrink-0">
                  <div class="flex items-center gap-2">
                    <span class="px-2 py-0.5 rounded-full bg-white/10 text-gray-200 uppercase text-[10px] font-medium">
                      <%= kind %>
                    </span>
                    <span class="px-2 py-0.5 rounded-full bg-white/10 text-gray-200 text-[10px] font-medium">
                      <%= share.ip %>:<%= share.port %>
                    </span>
                  </div>
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

  defp kind_icon("access"), do: "hero-arrows-right-left"
  defp kind_icon("host"), do: "hero-server-stack"
  defp kind_icon(_), do: "hero-question-mark-circle"
end

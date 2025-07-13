defmodule TunneldWeb.Live.Components.Artifacts do
  @moduledoc """
  Artifacts that are available and connected as devices to the system.
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:artifacts")
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    # Example list of artifacts, each with a type and a status.
    socket =
      socket
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the artifacts.
  """
  def render(assigns) do
    assigns =
      assigns
      |> assign(artifacts: assigns.data)

    ~H"""
    <div class="p-5">
      <div class="mb-5 flex flex-row">
        <div class="flex-1">
          <div class="text-xl text-gray-1 font-medium">Artifacts</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Add an Artifact"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Tunneld.Schema.Artifact.data(:add),
              "default_values" => %{},
              "action" => "add_artifact"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
        >
          <.icon class="w-6 h-6" name="hero-cpu-chip" />
          <div class="truncate text-xs">Add Artifact</div>
        </div>
      </div>

      <div>
        <div
          :if={Enum.empty?(@artifacts)}
          class="w-[100px] md:w-[60px] h-[100px] md:h-[60px] bg-secondary flex items-center justify-center rounded-md opacity-10"
        >
          <.icon class="w-8 h-8 text-white" name="hero-cpu-chip" />
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <%= if !Enum.empty?(@artifacts) do %>
            <%= for artifact <- @artifacts do %>
              <div
                phx-click="show_details"
                phx-value-type="artifact"
                phx-value-id={artifact.id || artifact["id"]}
                class="p-4 flex flex-col bg-secondary rounded-lg w-full h-[80px] cursor-pointer"
                style="animation: fadeIn 0.5s ease-out forwards;"
              >
                <div class="flex flex-row items-center">
                  <div class="grow">
                    <div class="text-lg bold truncate"><%= artifact.name %></div>
                  </div>
                  <div class={"w-3 h-3 rounded-full " <> get_status_color(artifact.status || false)} />
                </div>
                <div class="grow py-2" />
                <div class="text-sm truncate"><%= artifact.port %></div>
                <div class="text-sm truncate">
                  <a
                    :if={not Enum.empty?(artifact.tunnel)}
                    href={"https://" <> artifact.tunnel["subdomain"]}
                    class="flex flex-row items-center justify-center"
                    target="_blank"
                  >
                    <div class="grow">
                      <%= artifact.tunnel["subdomain"] %>
                    </div>
                    <.icon class="w-[18px] h-[18px]" name="hero-arrow-top-right-on-square" />
                  </a>
                  <span :if={Enum.empty?(artifact.tunnel)}>Not Connected</span>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper function to set a status indicator color based on artifact status.
  defp get_status_color(true), do: "bg-green"
  defp get_status_color(_), do: "bg-red"
end

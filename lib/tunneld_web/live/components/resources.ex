defmodule TunneldWeb.Live.Components.Resources do
  @moduledoc """
  Resources that are available and connected as devices to the system.
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:resources")
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    # Example list of resources, each with a type and a status.
    socket =
      socket
      |> assign(data: Map.get(assigns, :data, %{}))

    {:ok, socket}
  end

  @doc """
  Render the resources.
  """
  def render(assigns) do
    assigns =
      assigns
      |> assign(resources: assigns.data)

    ~H"""
    <div class="p-3 md:p-5">
      <div class="mb-4 md:mb-5 flex flex-row items-center gap-2">
        <div class="flex-1">
          <div class="text-lg md:text-xl text-gray-1 font-medium">Resources</div>
          <div class="mt-1 w-5 border-b-2 border-gray-1"></div>
        </div>
        <div class="flex flex-row items-center gap-2">
          <div
            phx-click="modal_open"
            phx-value-modal_title="Quick Expose"
            phx-value-modal_body={
              Jason.encode!(%{
                "type" => "code_blocks",
                "data" => quick_expose_blocks()
              })
            }
            class="flex items-center gap-1 text-gray-1 cursor-pointer hover:text-white transition-all"
          >
            <.icon name="hero-information-circle" class="h-4 w-4" />
            <span class="hidden sm:block text-xs">Quick Expose</span>
          </div>
          <div class="flex flex-row gap-1">
          <div
            phx-click="modal_open"
            phx-value-modal_title="Add Private Resource"
            phx-value-modal_body={
              Jason.encode!(%{
                "type" => "schema",
                "data" => Tunneld.Schema.Resource.data(:add_private),
                "default_values" => %{
                  "ip" => "0.0.0.0",
                  "port" => "",
                  "pool" => []
                },
                "action" => "add_private_share"
              })
            }
            phx-click-loading="opacity-50 cursor-wait"
            class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
          >
            <.icon class="w-5 h-5 sm:w-6 sm:h-6" name="hero-cpu-chip" />
            <div class="hidden sm:block truncate text-xs">Bind Private</div>
          </div>

          <div
            phx-click="modal_open"
            phx-value-modal_title="Add Resource"
            phx-value-modal_body={
              Jason.encode!(%{
                "type" => "schema",
                "data" => Tunneld.Schema.Resource.data(:add_public),
                "default_values" => %{
                  "ip" => "127.0.0.1",
                  "port" => "18000",
                  "pool" => []
                },
                "action" => "add_share"
              })
            }
            phx-click-loading="opacity-50 cursor-wait"
            class="flex items-center justify-center gap-1 bg-primary hover:bg-secondary p-2 transition-all cursor-pointer rounded-md duration-150 text-gray-1"
          >
            <.icon class="w-5 h-5 sm:w-6 sm:h-6" name="hero-cpu-chip" />
            <div class="hidden sm:block truncate text-xs">Add Resource</div>
          </div>
        </div>
      </div>
    </div>

    <div>
        <div
          :if={Enum.empty?(@resources)}
          class="w-[60px] h-[60px] bg-secondary flex items-center justify-center rounded-md opacity-10"
        >
          <.icon class="w-8 h-8 text-white" name="hero-cpu-chip" />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
          <%= if !Enum.empty?(@resources) do %>
            <%= for resource <- @resources do %>
              <% kind = resource.kind || "host" %>
              <div
                phx-click="show_details"
                phx-value-type="resource"
                phx-value-id={resource.id || resource["id"]}
                class="p-3 gap-2 flex flex-col rounded-lg w-full h-[80px] cursor-pointer bg-secondary transition-colors duration-150"
                style="animation: fadeIn 0.5s ease-out forwards;"
              >
                <div class="flex items-center gap-2 grow">
                  <.icon class="w-5 h-5 shrink-0" name={kind_icon(kind)} />
                  <div class="grow">
                    <div class="text-xs font-semibold truncate"><%= resource.name %></div>
                  </div>
                </div>

                <div class="flex items-center justify-between text-xs flex-shrink-0">
                  <div class="flex items-center gap-2">
                    <span class="px-2 py-0.5 rounded-full bg-white/10 text-gray-200 uppercase text-[10px] font-medium">
                      <%= kind %>
                    </span>
                    <%= if kind == "host" do %>
                      <% health = Map.get(resource, :health) || Map.get(resource, "health") || %{} %>
                      <span class={"w-[13px] h-[13px] rounded-full inline-block #{pool_health_dot(health[:status])}"}></span>
                    <% end %>
                    <%= if get_in(resource.tunneld, ["expose_source"]) == "device" do %>
                      <span class="px-2 py-0.5 rounded-full bg-white/10 text-gray-200 uppercase text-[10px] font-medium">QE</span>
                    <% end %>
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

  defp kind_icon("access"), do: "hero-arrows-right-left"
  defp kind_icon("host"), do: "hero-server-stack"
  defp kind_icon(_), do: "hero-question-mark-circle"

  defp pool_health_dot(:all_up), do: "bg-green"
  defp pool_health_dot(:none), do: "bg-red"
  defp pool_health_dot(:partial), do: "bg-yellow"
  defp pool_health_dot(_), do: "bg-gray-500"

  defp quick_expose_blocks do
    case gateway_host() do
      nil ->
        [%{"title" => "Error", "code" => "Gateway IP not configured"}]

      host ->
        [
          %{
            "title" => "Create a share",
            "code" => """
            curl -X POST http://#{host}/api/v1/expose \
              -H 'Content-Type: application/json' \
              -d '{"port": 3000, "name": "myapp"}'
            """
            |> String.trim_trailing()
          },
          %{
            "title" => "List your shares",
            "code" => "curl http://#{host}/api/v1/expose"
          },
          %{
            "title" => "Remove a share",
            "code" => "curl -X DELETE http://#{host}/api/v1/expose/myapp"
          }
        ]
    end
  end

  defp gateway_host do
    network = Application.get_env(:tunneld, :network, [])
    Keyword.get(network, :gateway)
  end
end

defmodule TunneldWeb.Live.Components.Resources do
  @moduledoc """
  Resources that are available and connected as devices to the system.
  """
  use TunneldWeb, :live_component
  import TunneldWeb.Live.Components.SectionHeader

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:resources")
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
  Render the resources.
  """
  def render(assigns) do
    assigns =
      assigns
      |> assign(resources: assigns.data)

    ~H"""
    <div>
      <.section_header>
        Resources
        <:actions>
          <button phx-click="modal_open" phx-value-modal_title="Quick Expose" phx-value-modal_body={Jason.encode!(%{"type" => "code_blocks", "data" => quick_expose_blocks()})} class="ghost-btn">
            Quick Expose
          </button>
          <button phx-click="modal_open" phx-value-modal_title="Add Resource" phx-value-modal_body={Jason.encode!(%{"type" => "schema", "data" => Tunneld.Schema.Resource.data(:add_public), "default_values" => %{"ip" => "127.0.0.1", "port" => "18000", "pool" => []}, "action" => "add_share"})} class="ghost-btn">
            Add Resource
          </button>
        </:actions>
      </.section_header>

      <div :if={Enum.empty?(@resources)} class="w-[60px] h-[60px] bg-surface flex items-center justify-center rounded-md opacity-10">
        <.icon class="w-8 h-8 text-text-primary" name="hero-cpu-chip" />
      </div>

      <div :if={!Enum.empty?(@resources)} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <%= for resource <- @resources do %>
          <% kind = resource.kind || "host" %>
          <div
            phx-click="show_details"
            phx-value-type="resource"
            phx-value-id={resource.id || resource["id"]}
            class="p-3 gap-2 flex flex-col rounded-lg w-full h-[80px] cursor-pointer bg-surface border border-border transition-colors duration-150 hover:bg-[#17161F] hover:border-[#2A2838]"
            style="animation: fadeIn 0.5s ease-out forwards;"
          >
            <div class="flex items-center gap-2 grow">
              <.icon class="w-5 h-5 shrink-0" name={kind_icon(kind)} />
              <div class="grow">
                <div class="text-xs font-semibold truncate"><%= mask(@obfuscated, resource.name) %></div>
              </div>
            </div>
            <div class="flex items-center justify-between text-xs flex-shrink-0">
              <div class="flex items-center gap-2">
                <span class="px-2 py-0.5 rounded-full bg-text-primary/10 text-text-secondary uppercase text-[10px] font-medium">
                  <%= kind %>
                </span>
                <%= if kind == "host" do %>
                  <% health = Map.get(resource, :health) || Map.get(resource, "health") || %{} %>
                  <span class={"w-[13px] h-[13px] rounded-full inline-block #{pool_health_dot(health[:status])}"}></span>
                <% end %>
                <%= if Map.get(resource, :expose_source) == "device" do %>
                  <span class="px-2 py-0.5 rounded-full bg-text-primary/10 text-text-secondary uppercase text-[10px] font-medium">QE</span>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp kind_icon("host"), do: "hero-server-stack"
  defp kind_icon(_), do: "hero-question-mark-circle"

  defp pool_health_dot(:all_up), do: "bg-green"
  defp pool_health_dot(:none), do: "bg-red"
  defp pool_health_dot(:partial), do: "bg-yellow"
  defp pool_health_dot(_), do: "bg-text-tertiary"

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

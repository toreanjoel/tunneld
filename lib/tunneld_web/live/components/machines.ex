defmodule TunneldWeb.Live.Components.Machines do
  @moduledoc """
  Managed machines LiveView component: a flat list of enrolled machines,
  per-machine probe/containers actions, and the enrollment flow.

  State on disk is a hint; capabilities and containers are fetched live
  over SSH (or mock) on click, never cached as truth.
  """

  use TunneldWeb, :live_component
  import TunneldWeb.Live.Components.SectionHeader

  alias Tunneld.Machines

  @impl true
  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:machines")
    end

    {:ok, assign(socket, machines: Machines.list(), selected: nil, containers: [], loading: false)}
  end

  @impl true
  def update(assigns, socket) do
    selected_id = socket.assigns[:selected] && socket.assigns[:selected]["id"]

    containers =
      if selected_id do
        case Machines.list_containers(selected_id) do
          {:ok, c} -> c
          _ -> []
        end
      else
        Map.get(assigns, :containers, [])
      end

    socket =
      socket
      |> assign(:obfuscated, Map.get(assigns, :obfuscated, false))
      |> assign(:machines, Machines.list())
      |> assign(:containers, containers)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_machine", %{"id" => id}, socket) do
    # Route to the dashboard sidebar (like resources/settings) instead of
    # rendering machine details inline. Send the event to the parent LiveView.
    send(socket.parent_pid || self(), {:show_details, %{"id" => id, "type" => "machine"}})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.section_header>
        Machines
        <:actions>
          <button phx-click="enroll_machine_modal" class="ghost-btn">
            Add Machine
          </button>
        </:actions>
      </.section_header>

      <div :if={Enum.empty?(@machines)} class="w-[60px] h-[60px] bg-surface flex items-center justify-center rounded-md opacity-10">
        <.icon class="w-8 h-8 text-text-primary" name="hero-server-stack" />
      </div>

      <div :if={not Enum.empty?(@machines)} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <%= for machine <- @machines do %>
          <div
            phx-click="select_machine"
            phx-target={@myself}
            phx-value-id={machine["id"]}
            class="p-3 gap-2 flex flex-col rounded-lg w-full cursor-pointer bg-surface border border-border transition-colors duration-150 hover:bg-[#17161F] hover:border-[#2A2838]"
          >
            <div class="flex items-center gap-2 grow">
              <.icon class="w-5 h-5 shrink-0" name="hero-server" />
              <div class="grow">
                <div class="text-xs font-semibold truncate"><%= machine["name"] %></div>
                <div class="text-[10px] text-text-tertiary truncate"><%= machine["address"] %></div>
              </div>
            </div>
            <div class="flex items-center justify-between text-xs">
              <span class="flex items-center gap-1.5">
                <span class={"w-[9px] h-[9px] rounded-full inline-block #{status_dot(machine["status"])}"}></span>
                <span class="px-2 py-0.5 rounded-full bg-text-primary/10 text-text-secondary uppercase text-[10px] font-medium">
                  <%= machine["kind"] %>
                </span>
              </span>
              <span class={"px-2 py-0.5 rounded-full uppercase text-[10px] font-medium #{location_chip(machine["location"])}"}>
                <%= location_label(machine["location"]) %>
              </span>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @selected do %>
        <.machine_detail machine={@selected} containers={@containers} loading={@loading} />
      <% end %>
    </div>
    """
  end

  defp machine_detail(_assigns), do: nil

  defp status_dot("ready"), do: "bg-green"
  defp status_dot("enrolled"), do: "bg-yellow"
  defp status_dot("probing"), do: "bg-yellow"
  defp status_dot("unreachable"), do: "bg-red"
  defp status_dot(_), do: "bg-gray-500"

  defp location_chip("remote"), do: "bg-blue-500/15 text-blue-400"
  defp location_chip(_), do: "bg-emerald-500/15 text-emerald-400"

  defp location_label("remote"), do: "remote"
  defp location_label(_), do: "local"
end
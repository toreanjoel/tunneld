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
    containers =
      case Machines.list_containers(id) do
        {:ok, c} -> c
        _ -> []
      end

    case Machines.get(id) do
      {:ok, machine} -> {:noreply, assign(socket, selected: machine, containers: containers)}
      _ -> {:noreply, socket}
    end
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

  defp machine_detail(assigns) do
    ~H"""
    <div class="mt-4 bg-surface border border-border rounded-lg p-4 space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm font-medium"><%= @machine["name"] %></div>
          <div class="text-xs text-text-tertiary"><%= @machine["address"] %> · <%= @machine["kind"] %> · <%= location_label(@machine["location"]) %></div>
        </div>
        <div class="flex gap-2">
          <button phx-click="probe_machine" phx-value-id={@machine["id"]} class="ghost-btn text-xs">Probe</button>
          <button phx-click="create_container_modal" phx-value-id={@machine["id"]} class="ghost-btn text-xs">New Container</button>
          <button phx-click="remove_machine" phx-value-id={@machine["id"]} class="ghost-btn !text-red text-xs">Remove</button>
        </div>
      </div>

      <%= if @machine["capabilities"] do %>
        <div class="text-xs text-text-secondary grid grid-cols-2 gap-2">
          <div>Incus: <%= @machine["capabilities"]["incus_version"] %></div>
          <div>OS: <%= @machine["capabilities"]["os"] %></div>
          <div>CPU: <%= @machine["capabilities"]["cpu_count"] %></div>
          <div>RAM: <%= @machine["capabilities"]["memory_mb"] %> MB</div>
          <div>KVM: <%= @machine["capabilities"]["kvm"] %></div>
          <div>GPU: <%= @machine["capabilities"]["gpu"] %></div>
        </div>
      <% end %>

      <div class="text-xs text-text-tertiary">
        Status: <%= @machine["status"] %>
        <%= if @machine["last_seen"], do: " · last seen #{String.slice(@machine["last_seen"], 0, 19)}" %>
      </div>

      <div>
        <div class="text-xs text-text-secondary mb-2">Containers</div>
        <%= if @loading do %>
          <div class="text-xs text-text-tertiary">Loading...</div>
        <% else %>
          <%= if Enum.empty?(@containers) do %>
            <div class="text-xs text-text-tertiary italic">No containers</div>
          <% else %>
            <div class="space-y-1">
              <%= for c <- @containers do %>
                <div class="flex items-center justify-between bg-surface-2 rounded p-2 text-xs">
                  <div class="flex items-center gap-2">
                    <span class={"w-2 h-2 rounded-full #{container_dot(c["status"])}"}></span>
                    <span class="font-mono"><%= c["name"] %></span>
                    <span class="text-text-tertiary"><%= c["type"] %></span>
                    <%= if c["ipv4"] != "" and c["ipv4"] != nil do %>
                      <span class="text-text-tertiary">· <%= c["ipv4"] %></span>
                    <% end %>
                  </div>
                  <div class="flex gap-1">
                    <button phx-click="open_terminal" phx-value-id={@machine["id"]} phx-value-name={c["name"]} class="ghost-btn !px-2 !py-0.5 text-[10px]">shell</button>
                    <button phx-click="start_container" phx-value-id={@machine["id"]} phx-value-name={c["name"]} class="ghost-btn !px-2 !py-0.5 text-[10px]">start</button>
                    <button phx-click="stop_container" phx-value-id={@machine["id"]} phx-value-name={c["name"]} class="ghost-btn !px-2 !py-0.5 text-[10px]">stop</button>
                    <%= if @machine["location"] == "remote" do %>
                      <button phx-click="expose_container_modal" phx-value-id={@machine["id"]} phx-value-name={c["name"]} class="ghost-btn !px-2 !py-0.5 text-[10px]">expose</button>
                    <% end %>
                    <button phx-click="delete_container" phx-value-id={@machine["id"]} phx-value-name={c["name"]} class="ghost-btn !text-red !px-2 !py-0.5 text-[10px]">delete</button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_dot("ready"), do: "bg-green"
  defp status_dot("enrolled"), do: "bg-yellow"
  defp status_dot("probing"), do: "bg-yellow"
  defp status_dot("unreachable"), do: "bg-red"
  defp status_dot(_), do: "bg-gray-500"

  defp location_chip("remote"), do: "bg-blue-500/15 text-blue-400"
  defp location_chip(_), do: "bg-emerald-500/15 text-emerald-400"

  defp location_label("remote"), do: "remote"
  defp location_label(_), do: "local"

  defp container_dot("Running"), do: "bg-green"
  defp container_dot("Stopped"), do: "bg-red"
  defp container_dot(_), do: "bg-gray-500"
end
defmodule TunneldWeb.Live.Components.Machines do
  @moduledoc """
  Managed machines LiveView component: a flat list of enrolled machines,
  per-machine probe actions, and the enrollment flow.

  State on disk is a hint; capabilities are fetched live
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

    {:ok, assign(socket, machines: Machines.list(), selected: nil, loading: false)}
  end

  @impl true
  def update(assigns, socket) do
    machines =
      Machines.list()
      |> Enum.map(&enrich/1)

    socket =
      socket
      |> assign(:obfuscated, Map.get(assigns, :obfuscated, false))
      |> assign(:machines, machines)

    {:ok, socket}
  end

  # Attach overlay IP and WireGuard status for the card.
  # Tolerates mock/unavailable so the UI never crashes.
  defp enrich(machine) do
    overlay_ip = Tunneld.Overlay.address_for(machine)

    wg =
      case Tunneld.Overlay.status(machine) do
        {:ok, %{up: true}} -> "up"
        {:ok, _} -> "down"
        _ -> nil
      end

    machine
    |> Map.put("overlay_ip", overlay_ip)
    |> Map.put("overlay_status", wg)
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

      <div
        :if={Enum.empty?(@machines)}
        class="w-[60px] h-[60px] bg-surface flex items-center justify-center rounded-md opacity-10"
      >
        <.icon class="w-8 h-8 text-text-primary" name="hero-server-stack" />
      </div>

      <div
        :if={not Enum.empty?(@machines)}
        class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3"
      >
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
              <span class="flex items-center gap-1.5" title={combined_status_tooltip(machine)}>
                <span class={"w-[9px] h-[9px] rounded-full inline-block #{combined_status_dot(machine)}"}>
                </span>
              </span>
              <span class={"px-2 py-0.5 rounded-full uppercase text-[10px] font-medium #{location_chip(machine["location"])}"}>
                <%= location_label(machine["location"]) %>
              </span>
            </div>
            <%!-- Overlay address only. The detected runtime used to sit next to it,
                 but "docker" says nothing about this machine that the operator
                 acts on - the same box could run the same service under any
                 runtime. Runtimes stay where they are useful: annotating the
                 listeners in the machine panel. --%>
            <div :if={machine["overlay_ip"]} class="text-[10px] text-text-tertiary">
              <span class="font-mono"><%= machine["overlay_ip"] %></span>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @selected do %>
        <.machine_detail machine={@selected} loading={@loading} />
      <% end %>
    </div>
    """
  end

  defp machine_detail(_assigns), do: nil

  # Combined status: unreachable (red) / reachable but overlay down (yellow) / fully up (green)
  defp combined_status_dot(machine) do
    status = machine["status"]
    wg = machine["overlay_status"]

    cond do
      status == "unreachable" -> "bg-red"
      status in ["ready"] and wg == "up" -> "bg-green"
      status in ["ready"] and wg != "up" -> "bg-yellow"
      status in ["enrolled", "probing"] -> "bg-yellow"
      true -> "bg-gray-500"
    end
  end

  defp combined_status_tooltip(machine) do
    status = machine["status"]
    wg = machine["overlay_status"]

    wg_detail = if wg, do: ", WG #{wg}", else: ""
    "Status: #{status}#{wg_detail}"
  end

  defp location_chip("remote"), do: "bg-blue-500/15 text-blue-400"
  defp location_chip(_), do: "bg-emerald-500/15 text-emerald-400"

  defp location_label("remote"), do: "remote"
  defp location_label(_), do: "local"
end

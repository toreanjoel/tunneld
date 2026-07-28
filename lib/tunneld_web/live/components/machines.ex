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

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:machines")
    end

    {:ok, assign(socket, machines: Machines.list(), selected: nil, containers: [], loading: false, show_enroll: false, show_create: false)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:obfuscated, Map.get(assigns, :obfuscated, false))
      |> assign(:machines, Machines.list())

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.section_header>
        Machines
        <:actions>
          <button phx-click="toggle_enroll" class="ghost-btn">
            Add Machine
          </button>
        </:actions>
      </.section_header>

      <div :if={Enum.empty?(@machines) and not @show_enroll} class="w-[60px] h-[60px] bg-surface flex items-center justify-center rounded-md opacity-10">
        <.icon class="w-8 h-8 text-text-primary" name="hero-server-stack" />
      </div>

      <div :if={not Enum.empty?(@machines)} class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <%= for machine <- @machines do %>
          <div
            phx-click="select_machine"
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
              <span class="px-2 py-0.5 rounded-full bg-text-primary/10 text-text-secondary uppercase text-[10px] font-medium">
                <%= machine["kind"] %>
              </span>
              <span class={"w-[13px] h-[13px] rounded-full inline-block #{status_dot(machine["status"])}"}></span>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @show_enroll do %>
        <.enroll_form />
      <% end %>

      <%= if @selected do %>
        <.machine_detail machine={@selected} containers={@containers} loading={@loading} show_create={@show_create} />
      <% end %>
    </div>
    """
  end

  defp enroll_form(assigns) do
    ~H"""
    <div class="mt-4 bg-surface border border-border rounded-lg p-4">
      <div class="text-sm font-medium mb-3">Add a machine</div>
      <form phx-submit="enroll_machine" class="space-y-3">
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Name</label>
          <input type="text" name="name" placeholder="office-box" class="tunl-input" />
        </div>
        <div>
          <label class="text-xs text-text-secondary mb-1 block">Address (host or IP)</label>
          <input type="text" name="address" placeholder="10.0.0.5" class="tunl-input" />
        </div>
        <div>
          <label class="text-xs text-text-secondary mb-1 block">SSH port</label>
          <input type="number" name="ssh_port" value="22" class="tunl-input" />
        </div>
        <button type="submit" class="w-full p-3 rounded-lg text-sm font-medium transition bg-accent hover:bg-accent-light">
          Generate Key & Enroll
        </button>
      </form>
    </div>
    """
  end

  defp machine_detail(assigns) do
    ~H"""
    <div class="mt-4 bg-surface border border-border rounded-lg p-4 space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm font-medium"><%= @machine["name"] %></div>
          <div class="text-xs text-text-tertiary"><%= @machine["address"] %> · <%= @machine["kind"] %></div>
        </div>
        <div class="flex gap-2">
          <button phx-click="probe_machine" phx-value-id={@machine["id"]} class="ghost-btn text-xs">Probe</button>
          <button phx-click="toggle_create" phx-value-id={@machine["id"]} class="ghost-btn text-xs">New Container</button>
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

      <%= if @show_create do %>
        <.create_form machine_id={@machine["id"]} />
      <% end %>

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

  defp create_form(assigns) do
    ~H"""
    <form phx-submit="create_container" phx-value-id={@machine_id} class="bg-surface-2 rounded p-3 space-y-2">
      <div class="text-xs font-medium">New container/VM</div>
      <input type="text" name="name" placeholder="my-app" class="tunl-input" />
      <input type="text" name="image" placeholder="ubuntu/24.04" class="tunl-input" />
      <select name="type" class="tunl-input">
        <option value="container">container</option>
        <option value="vm">vm</option>
      </select>
      <input type="number" name="cpu" placeholder="cpu (optional)" class="tunl-input" />
      <input type="number" name="memory" placeholder="memory MiB (optional)" class="tunl-input" />
      <button type="submit" class="w-full p-2 rounded text-xs font-medium bg-accent hover:bg-accent-light">Create</button>
    </form>
    """
  end

  defp status_dot("ready"), do: "bg-green"
  defp status_dot("enrolled"), do: "bg-yellow"
  defp status_dot("probing"), do: "bg-yellow"
  defp status_dot("unreachable"), do: "bg-red"
  defp status_dot(_), do: "bg-gray-500"

  defp container_dot("Running"), do: "bg-green"
  defp container_dot("Stopped"), do: "bg-red"
  defp container_dot(_), do: "bg-gray-500"
end
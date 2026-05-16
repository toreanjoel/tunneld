defmodule TunneldWeb.Live.Components.ResourcesSection do
  @moduledoc """
  Resources grid with section header and action buttons (Quick Expose, Bind Private, Add Resource).
  """
  use Phoenix.Component
  import TunneldWeb.Icons
  import TunneldWeb.Live.Components.SectionHeader
  import TunneldWeb.Live.Components.HelpIcon

  attr :resources, :list, default: []

  def resources_section(assigns) do
    ~H"""
    <section>
      <.section_header>
        Resources<.help_icon text="Services and applications registered on your network. Each resource has a backend pool (IP addresses and ports), a public Zrok share for internet access, and optionally a private share with token-based access. Bind private resources from other nodes to access their services locally." />
        <:actions>
          <button class="ghost-btn" phx-click="modal_open" phx-value-modal_title="Quick Expose" phx-value-modal_body={
            Jason.encode!(%{"type" => "code_blocks", "data" => quick_expose_blocks()})
          }>
            <.zap size={16} /> Quick expose
          </button>
          <button class="ghost-btn" phx-click="modal_open" phx-value-modal_title="Add Private Resource" phx-value-modal_body={
            Jason.encode!(%{"type" => "schema", "data" => Tunneld.Schema.Resource.data(:add_private), "default_values" => %{"ip" => "0.0.0.0", "port" => "", "pool" => []}, "action" => "add_private_share"})
          }>
            <.icons_link size={16} /> Bind private
          </button>
          <button class="ghost-btn" phx-click="modal_open" phx-value-modal_title="Add Resource" phx-value-modal_body={
            Jason.encode!(%{"type" => "schema", "data" => Tunneld.Schema.Resource.data(:add_public), "default_values" => %{"ip" => "127.0.0.1", "port" => "18000", "pool" => []}, "action" => "add_share"})
          }>
            <.plus size={16} /> Add resource
          </button>
        </:actions>
      </.section_header>

      <div :if={Enum.empty?(@resources)} class="text-text-tertiary text-sm py-8 text-center">
        No resources configured
      </div>

      <div :if={!Enum.empty?(@resources)} class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <%= for resource <- @resources do %>
          <.host_card resource={resource} />
        <% end %>
      </div>
    </section>
    """
  end

  attr :resource, :map, required: true

  defp host_card(assigns) do
    r = assigns.resource
    name = Map.get(r, :name) || Map.get(r, "name") || "—"
    kind = Map.get(r, :kind) || Map.get(r, "kind") || "host"
    id = Map.get(r, :id) || Map.get(r, "id")
    ip = Map.get(r, :ip) || Map.get(r, "ip")
    port = Map.get(r, :port) || Map.get(r, "port")
    addr = if ip && port, do: "#{ip}:#{port}", else: ip || "—"

    assigns = assign(assigns, name: name, kind: kind, id: id, addr: addr)

    ~H"""
    <div
      class="bg-surface border border-border rounded-xl p-5 h-[104px] flex flex-col justify-between cursor-pointer relative transition-colors duration-[120ms] group hover:bg-[#17161F] hover:border-[#2A2838]"
      phx-click="show_details" phx-value-type="resource" phx-value-id={@id}
    >
      <div class="flex items-center gap-2.5">
        <span class="text-text-secondary inline-flex">
          <.server size={18} />
        </span>
        <span class="text-base text-text-primary font-medium"><%= @name %></span>
      </div>
      <div class="flex justify-between items-center">
        <span class="bg-surface-2 text-text-secondary px-2.5 py-1 rounded-md text-[11px] tracking-[0.08em] uppercase font-medium">
          <%= @kind %>
        </span>
        <span class="status-dot status-dot--green" />
      </div>
      <div class="hidden group-hover:block absolute -bottom-0 left-5 translate-y-full bg-black border border-border rounded-md px-2.5 py-1.5 font-mono text-xs text-text-primary whitespace-nowrap z-[5]">
        <%= @addr %>
      </div>
    </div>
    """
  end

  defp quick_expose_blocks do
    case gateway_host() do
      nil -> [%{"title" => "Error", "code" => "Gateway IP not configured"}]
      host ->
        [
          %{"title" => "Create a share", "code" => "curl -X POST http://#{host}/api/v1/expose \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"port\": 3000, \"name\": \"myapp\"}'"},
          %{"title" => "List your shares", "code" => "curl http://#{host}/api/v1/expose"},
          %{"title" => "Remove a share", "code" => "curl -X DELETE http://#{host}/api/v1/expose/myapp"}
        ]
    end
  end

  defp gateway_host do
    Application.get_env(:tunneld, :network, []) |> Keyword.get(:gateway)
  end
end

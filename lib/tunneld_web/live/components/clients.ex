defmodule TunneldWeb.Live.Components.Clients do
  @moduledoc """
  People, as opposed to machines: the phones and laptops that reach this subnet
  over WireGuard.

  Enrolling shows the config and its QR **once** - the private key is generated
  on the gateway, handed over, and never stored (see `Tunneld.Clients`). So the
  panel is deliberately blunt about that: there is no "show again", only revoke
  and re-enrol.
  """
  use TunneldWeb, :live_component

  import TunneldWeb.Live.Components.SectionHeader

  alias Tunneld.Clients

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:clients, Clients.list())
     |> assign(:endpoints, endpoints())
     |> assign(:obfuscated, Map.get(assigns, :obfuscated, false))
     |> assign_new(:issued, fn -> nil end)}
  end

  @impl true
  def handle_event("enroll_client", %{"name" => name} = params, socket) do
    case Clients.enroll(name, endpoint: params["endpoint"]) do
      {:ok, client, config} ->
        {:noreply,
         socket
         |> assign(:clients, Clients.list())
         |> assign(:issued, %{client: client, config: config, qr: Clients.qr_svg(config)})}

      {:error, :name_required} ->
        notify(:error, "Give the device a name")
        {:noreply, socket}

      {:error, reason} ->
        notify(:error, "Could not enrol: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event("dismiss_issued", _params, socket),
    do: {:noreply, assign(socket, :issued, nil)}

  def handle_event("revoke_client", %{"id" => id}, socket) do
    Clients.revoke(id)
    notify(:info, "Client revoked - its key no longer works")
    {:noreply, socket |> assign(:clients, Clients.list()) |> assign(:issued, nil)}
  end

  defp notify(type, message),
    do: Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{type: type, message: message})

  # Where a client should dial. The gateway itself is the no-VPS path and is
  # listed first; every enrolled machine is a door to the same gateway.
  defp endpoints do
    gw = Tunneld.Config.gateway_ip() || "10.0.0.1"

    [{gw, "#{gw} — this gateway (home network only)"}] ++
      Enum.map(Tunneld.Machines.list(), fn m ->
        {m["address"], "#{m["address"]} — via #{m["name"]} (from anywhere)"}
      end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.section_header>
        Clients
        <:actions>
          <span class="text-xs text-text-tertiary">
            <%= length(@clients) %> enrolled
          </span>
        </:actions>
      </.section_header>

      <div :if={@issued} class="mb-3 p-3 bg-surface rounded-lg border border-accent/40">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="text-sm font-semibold">
              <%= @issued.client["name"] %> — scan or copy, once
            </p>
            <p class="text-xs text-text-tertiary mt-0.5">
              The private key is not stored. If this is lost, revoke and enrol again.
            </p>
          </div>
          <button
            phx-click="dismiss_issued"
            phx-target={@myself}
            class="ghost-btn !px-2 !py-0.5 text-[10px]"
          >
            Done
          </button>
        </div>

        <div class="flex flex-col md:flex-row gap-3 mt-3">
          <div class="shrink-0 bg-surface-2 rounded p-2"><%= Phoenix.HTML.raw(@issued.qr) %></div>
          <div class="relative min-w-0 flex-1">
            <pre class="bg-black/60 p-3 pr-14 rounded text-[10px] font-mono text-green-400 whitespace-pre-wrap break-all border border-gray-700"><%= @issued.config %></pre>
            <button
              type="button"
              id={"copy_client_#{@issued.client["id"]}"}
              phx-hook="CopyToClipboard"
              data-copy-text={@issued.config}
              class="absolute top-2 right-2 text-[10px] bg-surface-2 hover:bg-surface border border-border rounded px-2 py-1 text-text-secondary"
            >
              Copy
            </button>
          </div>
        </div>
      </div>

      <form phx-submit="enroll_client" phx-target={@myself} class="flex flex-wrap gap-1.5 mb-3">
        <input
          type="text"
          name="name"
          placeholder="Device name, e.g. partner-phone"
          class="tunl-input flex-1 min-w-[10rem] text-xs"
        />
        <select name="endpoint" class="tunl-input text-xs">
          <option :for={{value, label} <- @endpoints} value={value}><%= label %></option>
        </select>
        <button type="submit" class="ghost-btn text-xs">Add client</button>
      </form>

      <div :if={@clients == []} class="text-xs text-text-tertiary italic">
        No clients yet. Add one to reach this subnet from a phone or laptop.
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-1.5">
        <div
          :for={c <- @clients}
          class="flex items-center justify-between gap-2 p-2 bg-surface rounded-md"
        >
          <div class="min-w-0">
            <div class="text-sm truncate"><%= c["name"] %></div>
            <div class="text-[11px] text-text-tertiary font-mono truncate">
              <%= c["address"] %> · via <%= c["endpoint"] %>
              <%= if c["lan_access"] in [nil, []] do %>
                · overlay only
              <% else %>
                · <%= length(c["lan_access"]) %> LAN host(s)
              <% end %>
            </div>
          </div>
          <button
            phx-click="revoke_client"
            phx-value-id={c["id"]}
            phx-target={@myself}
            class="ghost-btn !px-2 !py-0.5 text-[10px] shrink-0"
          >
            Revoke
          </button>
        </div>
      </div>
    </div>
    """
  end
end

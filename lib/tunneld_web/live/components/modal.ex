defmodule TunneldWeb.Live.Components.Modal do
  @moduledoc """
  Reusable modal dialog component for the dashboard.

  Renders different content types (default overlay, JSON schema forms)
  and dispatches form actions back to the parent LiveView via PubSub.
  """
  use TunneldWeb, :live_component

  attr :modal_title, :string, required: true
  attr :modal_description, :string, required: false
  attr :modal_body, :any, required: true
  attr :modal_actions, :map, required: false
  attr :type, :atom, default: :default
  attr :client_id, :string, required: true
  attr :pending_actions, :map, default: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Render the different modal content --%>
      <%= content_type(assigns, @type) %>
    </div>
    """
  end

  @doc """
    Render the different modal content data type
  """
  def content_type(assigns, :default) do
    pending_actions = Map.get(assigns, :pending_actions, %{})

    assigns = assigns |> assign(pending_actions)

    ~H"""
    <div class="fixed inset-0 bg-secondary bg-opacity-80 flex items-center justify-center">
      <div class="bg-primary rounded-md p-6 max-w-[500px] lg:w-1/3 relative z-20">
        <%!-- closing the modal --%>
        <div phx-click="modal_close" class="absolute top-[0px] right-[0px] p-3 cursor-pointer">
          <.icon name="hero-x-mark-solid" class="h-5 w-5" />
        </div>
        <div class="py-2">
          <h2 class="text-xl"><%= @title %></h2>
          <h2 class="text-sm"><%= @description %></h2>
        </div>
         <!-- Render the dynamic body -->
         <div class="text-sm"><%= render_body(assigns, @body) %></div>
         <!-- Modal Actions -->
         <div :if={@body["type"] !== "schema"} class="flex justify-end space-x-3 pt-2 mt-3">
          <% action_loading =
            if @actions do
              @pending_actions
              |> Map.values()
              |> Enum.any?(fn %{action: pending_action} -> pending_action == @actions["payload"]["type"] end)
            else
              false
            end %>
          <button
            :if={@actions["title"]}
            phx-target={@myself}
            phx-click="modal_action"
            phx-value-type={@actions["payload"]["type"]}
            phx-value-data={Jason.encode!(@actions["payload"]["data"])}
            phx-value-client_id={@client_id}
            phx-disable-with="Working..."
            disabled={action_loading}
            class="text-sm font-light gap-1 bg-red hover:bg-opacity-60 p-3 cursor-pointer rounded-md"
          >
            <%= @actions["title"] %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("modal_action", %{"type" => action, "data" => data, "client_id" => client_id}, socket) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "modal:form:action:#{client_id}", %{
      action: action,
      data: data
    })

    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_code", %{"text" => text}, socket) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: :info,
      message: "Copied to clipboard"
    })

    {:noreply, push_event(socket, "copy_to_clipboard", %{text: text})}
  end

  defp render_body(_assigns, %{"type" => "string", "data" => data}) do
    data
  end

  defp render_body(assigns, %{"type" => "code", "data" => data}) do
    assigns = assign(assigns, :data, data)

    ~H"""
    <div class="mt-2">
      <p class="text-xs text-gray-300 mb-2">From any allowed device on the subnet, run:</p>
      <div class="relative">
        <pre class="bg-black/60 p-3 pr-10 rounded text-xs font-mono text-green-400 whitespace-pre-wrap border border-gray-700"><%= @data %></pre>
        <button
          phx-click="copy_code"
          phx-target={@myself}
          phx-value-text={@data}
          class="absolute top-2 right-2 p-1 rounded bg-gray-700 hover:bg-gray-600 text-gray-300 transition-colors"
          title="Copy to clipboard"
        >
          <.icon name="hero-clipboard" class="h-4 w-4" />
        </button>
      </div>
    </div>
    """
  end

  defp render_body(assigns, %{"type" => "code_blocks", "data" => blocks}) when is_list(blocks) do
    assigns = assign(assigns, :blocks, blocks)

    ~H"""
    <div class="mt-2 space-y-3">
      <p class="text-xs text-gray-300">From any allowed device on the subnet:</p>
      <%= for block <- @blocks do %>
        <div class="relative">
          <p class="text-[10px] uppercase font-medium text-gray-400 mb-0.5"><%= block["title"] %></p>
          <pre class="bg-black/60 p-3 pr-10 rounded text-xs font-mono text-green-400 whitespace-pre-wrap border border-gray-700"><%= block["code"] %></pre>
          <button
            phx-click="copy_code"
            phx-target={@myself}
            phx-value-text={block["code"]}
            class="absolute top-5 right-2 p-1 rounded bg-gray-700 hover:bg-gray-600 text-gray-300 transition-colors"
            title="Copy to clipboard"
          >
            <.icon name="hero-clipboard" class="h-4 w-4" />
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_body(
         assigns,
         %{
           "type" => "schema",
           "data" => data,
           "default_values" => default_values,
           "action" => action
         } = payload
       ) do
    pending_actions = Map.get(assigns, :pending_actions, %{})
    loading =
      pending_actions
      |> Map.values()
      |> Enum.any?(fn %{action: pending_action} -> pending_action == action end)

    # Reassign the default values so we can access it in the html
    assigns =
      assigns
      |> assign(data: data)
      |> assign(default_values: default_values)
      |> assign(action: action)
      # We do this so we can match with or without the title for backward compatibility
      |> assign(title: Map.get(payload, "title", "Submit"))
      |> assign(loading: loading)

    ~H"""
    <div>
      <.live_component
        id={"schema_form_#{@action}"}
        module={TunneldWeb.Live.Components.JsonSchemaRenderer}
        schema={@data}
        values={@default_values}
        action={@action}
        title={@title}
        client_id={@client_id}
        loading={@loading}
      />
    </div>
    """
  end

  defp render_body(_assigns, _), do: "There was a problem rendering the modal body"
end

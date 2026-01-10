defmodule TunneldWeb.Live.Components.Modal do
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

  defp render_body(_assigns, %{"type" => "string", "data" => data}) do
    data
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

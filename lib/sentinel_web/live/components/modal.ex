defmodule SentinelWeb.Live.Components.Modal do
  use SentinelWeb, :live_component

  attr :modal_title, :string, required: true
  attr :modal_body, :any, required: true
  attr :modal_actions, :map, required: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-secondary bg-opacity-80 flex items-center justify-center">
      <div class="bg-primary rounded-md p-6 max-w-[500px] lg:w-1/3 relative">
        <%!-- closing the modal --%>
        <div phx-click="close_modal" class="absolute top-[0px] right-[0px] p-3 cursor-pointer">
          <.icon name="hero-x-mark-solid" class="h-5 w-5" />
        </div>

        <h2 class="text-xl py-2"><%= @title %></h2>

        <!-- Render the dynamic body -->
        <div class="text-sm"><%= render_body(assigns, @body) %></div>

        <!-- Modal Actions -->
        <div :if={@body["type"] !== "schema"} class="flex justify-end space-x-3 pt-2">
          <button
            :if={@actions["title"]}
            phx-click="action"
            phx-target={@myself}
            phx-value-type={@actions["payload"]["type"]}
            phx-value-data={Jason.encode!(@actions["payload"]["data"])}
            class="text-sm font-light gap-1 bg-purple hover:bg-opacity-60 p-3 cursor-pointer rounded-md"
          >
            <%= @actions["title"] %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  #
  # Handle the modal action passed - this comes from the generated modal data
  # TODO: this needs to be expanded on but the the actions should not be in here
  #
  def handle_event("action", %{"type" => type, "data" => data}, socket) do
    decoded_data = Jason.decode!(data)
    # TODO: add the actions here that we do based on the modal action types
    IO.inspect(decoded_data, label: "CUSTOM_ACTION")
    raise "custom action?"
    case type do
      _ -> IO.inspect("HANDLE ACTION: Type: #{type}, DATA: #{inspect(decoded_data)}")
    end

    {:noreply, assign(socket, modal: %{show: false, title: nil, body: %{}, actions: nil})}
  end

  #
  # This is the renderer that will either use the schema or the string
  # TODO: if string and using normal actions, we need to try execute the function
  defp render_body(_assigns, %{"type" => "string", "data" => data}) do
    data
  end

  defp render_body(assigns, %{"type" => "schema", "data" => data, "default_values" => default_values}) do
    # Reassign the default values so we can access it in the html
    assigns =
      assigns
      |> assign(data: data)
      |> assign(default_values: default_values)

    ~H"""
      <div>
      <.live_component
          id={DateTime.utc_now()}
          module={SentinelWeb.Live.Components.JsonSchemaRenderer}
          schema={@data}
          values={@default_values}
        />
      </div>
    """
  end
  defp render_body(_assigns, _), do: "There was a problem rendering the modal body"
end

defmodule SentinelWeb.Live.Components.JsonSchemaRenderer do
  @moduledoc """
  A Phoenix LiveComponent that dynamically renders forms based on JSON Schema.
  """

  use Phoenix.LiveComponent
  alias ExJsonSchema.Validator
  alias ExJsonSchema.Schema

  @doc """
  Initializes or updates the component state.

  ## Assigns:
  - `schema` (map) - JSON schema for form structure.
  - `values` (map, optional) - Prepopulated form values.
  """
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    schema = Schema.resolve(assigns.schema)
    # Defaults to empty if not provided
    values = Map.get(assigns, :values, %{})

    fields =
      assigns.schema["properties"]
      |> Enum.map(fn {key, props} ->
        %{
          name: key,
          type: props["type"],
          description: props["description"],
          # Prioritize enums passed in `values` (dynamic injection)
          enum: Map.get(values, key, props["enum"]),
          format: props["format"]
        }
      end)

    {:ok, assign(socket, action: assigns.action, schema: schema, fields: fields, changeset: values, errors: nil)}
  end

  @doc """
  Renders a dynamic form based on the provided JSON schema.
  """
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <form phx-target={@myself} phx-submit="submit">
      <%= for field <- @fields do %>
        <div class="mb-4 capitalize">
          <label class="block text-white text-sm font-semibold mb-1">
            <%= field.name %>
          </label>
          <label :if={field.description} class="block text-white text-xs font-semibold mb-1">
            <%= field.description %>
          </label>

          <%= if field.enum do %>
            <!-- Select Dropdown for Enum Fields -->
            <select
              name={"form[#{field.name}]"}
              class="bg-primary rounded-md px-3 py-2 w-full"
            >
              <%= for option <- field.enum do %>
                <option value={option} selected={Map.get(@changeset, field.name, "") == option}>
                  <%= option %>
                </option>
              <% end %>
            </select>
          <% else %>
            <!-- Input Fields -->
            <%= case field.type do %>
              <% "string" -> %>
                <% input_type = if field.format === "password", do: "password", else: "text" %>
                <input
                  type={input_type}
                  name={"form[#{field.name}]"}
                  value={Map.get(@changeset, field.name, "")}
                  class="bg-primary rounded-md px-3 py-2 w-full text-gray-1 focus:ring-2 focus:ring-purple transition duration-200"
                />
              <% "integer" -> %>
                <input
                  type="number"
                  name={"form[#{field.name}]"}
                  value={Map.get(@changeset, field.name, "")}
                  class="bg-primary rounded-md px-3 py-2 w-full text-gray-1 focus:ring-2 focus:ring-purple transition duration-200"
                />
            <% end %>
          <% end %>
        </div>
      <% end %>

      <ul :if={@errors} class="bg-red bg-opacity-20 p-3 rounded-md mb-4">
        <%= for error <- @errors do %>
          <li class="text-red text-sm"><%= error %></li>
        <% end %>
      </ul>

      <div class="flex flex-row">
        <div class="grow w-full" />
        <button
          type="submit"
          class="bg-purple text-white px-4 py-2 rounded-lg font-semibold hover:bg-light_purple transition duration-200"
        >
          Submit
        </button>
      </div>
    </form>
    """
  end

  @doc """
  Submits the form after validation.
  """
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("submit", %{"form" => params}, socket) do
    case Validator.validate(socket.assigns.schema, params) do
      :ok ->
        # Send this back to the parent live view that handles the event already
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "modal:form:action", %{
          action: socket.assigns.action,
          data: params
        })

        {:noreply, assign(socket, changeset: params, errors: nil)}

      {:error, errors} ->
        {:noreply, assign(socket, changeset: params, errors: clean_errors(errors))}
    end
  end

  #
  # Validation error output
  #
  defp clean_errors(errors) do
    Enum.map(errors, fn {field, msg} ->
      "#{msg |> String.replace("#/", "") |> String.capitalize()} :: #{field}"
    end)
  end
end

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
    loading = Map.get(assigns, :loading, false)

    fields =
      assigns.schema["properties"]
      |> Enum.map(fn {key, props} ->
        %{
          name: key,
          type: props["type"],
          description: props["description"],
          # Prioritize enums passed in `values` (dynamic injection)
          enum: Map.get(values, key, props["enum"]),
          format: props["format"],
          default: props["default"],
          hidden: props["ui:widget"] == "hidden",
          readonly: props["readOnly"] == true
        }
      end)

    {:ok,
     socket
     |> assign(loading: loading)
     |> assign(action: assigns.action)
     |> assign(schema: schema)
     |> assign(fields: fields)
     |> assign(changeset: values)
     |> assign(errors: nil)}
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

          <%= if is_list(field.enum) do %>
            <!-- Select Dropdown for Enum Fields -->
            <select name={"form[#{field.name}]"} class="bg-primary rounded-md px-3 py-2 w-full">
              <%= for option <- field.enum do %>
                <option value={option} selected={Map.get(@changeset, field.name, "") == option}>
                  <%= option %>
                </option>
              <% end %>
            </select>
          <% else %>
            <%= if field.type == "boolean" do %>
              <input
                type="checkbox"
                name={"form[#{field.name}]"}
                value="true"
                checked={Map.get(@changeset, field.name) in [true, "true", "on", 1]}
                class="rounded border-gray-300 text-purple shadow-sm focus:ring-2 focus:ring-purple"
              />
            <% else %>
              <% input_type = if field.format == "password", do: "password", else: "text" %>
              <input
                type={input_type}
                name={"form[#{field.name}]"}
                value={Map.get(@changeset, field.name, field.default || "")}
                class="bg-primary rounded-md px-3 py-2 w-full text-gray-1 focus:ring-2 focus:ring-purple transition duration-200"
                readonly={field.readonly}
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
          class={"
            #{if not @loading, do: "bg-purple hover:bg-light_purple", else: "bg-light_purple"}
            text-white px-4 py-2 rounded-lg font-semibold
            transition duration-200"
          }
        >
          <%= if @loading, do: "Loading...", else: "Submit" %>
        </button>
      </div>
    </form>
    """
  end

  @doc """
  Submits the form after validation.
  """
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("submit", %{"form" => raw_params}, socket) do
    params =
      socket.assigns.fields
      |> Enum.reduce(%{}, fn field, acc ->
        value =
          case field.type do
            "boolean" ->
              # HTML checkboxes only send data when checked
              # So if the key is present, it's checked
              Map.has_key?(raw_params, field.name)

            _ ->
              Map.get(raw_params, field.name)
          end

        Map.put(acc, field.name, value)
      end)

    case Validator.validate(socket.assigns.schema, params) do
      :ok ->
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

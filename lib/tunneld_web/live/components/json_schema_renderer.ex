defmodule TunneldWeb.Live.Components.JsonSchemaRenderer do
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
    client_id = Map.get(assigns, :client_id, nil)

    # Defaults to empty if not provided
    title = Map.get(assigns, :title, "Submit")
    values = Map.get(assigns, :values, %{})
    loading = Map.get(assigns, :loading, false)
    existing_changeset = Map.get(socket.assigns, :changeset, %{})

    # This should allow a default of the keys that is already on the form to handle fallback order
    ui_order = Map.get(assigns.schema, "ui:order", assigns.schema["properties"] |> Map.keys())

    fields =
      ui_order
      |> Enum.map(fn key ->
        props = Map.get(assigns.schema["properties"], key, "")

        %{
          name: key,
          type: props["type"],
          description: props["description"],
          # Prioritize enums passed in `values` (dynamic injection)
          enum:
            if(props["type"] == "array",
              do: nil,
              else: Map.get(values, key, props["enum"])
            ),
          format: props["format"],
          default: props["default"],
          hidden: props["ui:widget"] == "hidden",
          readonly: props["readOnly"] == true,
          widget: props["ui:widget"],
          help: props["ui:help"]
        }
      end)

    changeset = if map_size(existing_changeset) > 0, do: existing_changeset, else: values

    {:ok,
     socket
     |> assign(title: title)
     |> assign(loading: loading)
     |> assign(action: assigns.action)
     |> assign(schema: schema)
     |> assign(fields: fields)
     # Preserve user-entered values during re-renders (e.g., while submitting)
     |> assign(changeset: changeset)
     |> assign(client_id: client_id)
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
        <div class="mb-4">
          <% hidden = if field.hidden, do: "hidden", else: "" %>

          <label class={"#{hidden} text-white text-sm font-semibold mb-1 capitalize"}>
            <%= field.name %>
          </label>
          <label
            :if={field.description}
            class={"#{hidden} block text-white text-xs font-semibold mb-1"}
          >
            <%= field.description %>
          </label>

          <%= if is_list(field.enum) do %>
            <%= if field.type == "array" do %>
              <textarea
                name={"form[#{field.name}]"}
                rows="5"
                class={"#{hidden} bg-primary rounded-md px-3 py-2 w-full text-gray-1 focus:ring-2 focus:ring-purple transition duration-200 font-mono text-sm"}
                readonly={field.readonly}
              ><%= array_to_text(Map.get(@changeset, field.name, field.default || [])) %></textarea>
              <div :if={field.help} class="bg-blue-800 bg-opacity-20 py-2 px-3 rounded-md my-2 text-xs text-blue-500">
                <%= field.help %>
              </div>
            <% else %>
              <!-- Enum dropdown -->
              <select
                name={"form[#{field.name}]"}
                class={"#{hidden} bg-primary rounded-md px-3 py-2 w-full"}
              >
                <%= for option <- field.enum do %>
                  <option value={option} selected={Map.get(@changeset, field.name, "") == option}>
                    <%= option %>
                  </option>
                <% end %>
              </select>
            <% end %>
          <% else %>
            <%= if field.type == "boolean" do %>
              <input
                type="checkbox"
                name={"form[#{field.name}]"}
                value="true"
                checked={Map.get(@changeset, field.name) in [true, "true", "on", 1]}
                class={"#{hidden} rounded border-gray-300 text-purple shadow-sm focus:ring-2 focus:ring-purple"}
              />
            <% else %>
              <%= if field.type == "array" do %>
                <textarea
                  name={"form[#{field.name}]"}
                  rows="5"
                  class={"#{hidden} bg-primary rounded-md px-3 py-2 w-full text-gray-1 focus:ring-2 focus:ring-purple transition duration-200 font-mono text-sm"}
                  readonly={field.readonly}
                ><%= array_to_text(Map.get(@changeset, field.name, field.default || [])) %></textarea>
                <div :if={field.help} class="bg-blue-800 bg-opacity-20 py-2 px-3 rounded-md my-2 text-xs text-blue-500">
                  <%= field.help %>
                </div>
              <% else %>
                <%= if field.widget == "textarea" do %>
                  <textarea
                    name={"form[#{field.name}]"}
                    rows="6"
                    class={"#{hidden} bg-primary rounded-md px-3 py-2 w-full text-gray-1 focus:ring-2 focus:ring-purple transition duration-200 font-mono text-sm"}
                    readonly={field.readonly}
                  ><%= Map.get(@changeset, field.name, field.default || "") %></textarea>
                <% else %>
                  <% input_type = if field.format == "password", do: "password", else: "text" %>
                  <input
                    type={input_type}
                    name={"form[#{field.name}]"}
                    value={Map.get(@changeset, field.name, field.default || "")}
                    class={"#{hidden} bg-primary rounded-md px-3 py-2 w-full text-gray-1 focus:ring-2 focus:ring-purple transition duration-200"}
                    readonly={field.readonly}
                  />
                  <div :if={field.help} class="bg-blue-800 bg-opacity-20 py-2 px-3 rounded-md my-2 text-xs text-blue-500">
                    <%= field.help %>
                  </div>
                <% end %>
              <% end %>
            <% end %>
          <% end %>
        </div>
      <% end %>

      <div :if={@errors} class="bg-red bg-opacity-20 p-3 rounded-md mb-4">
        <%= for error <- @errors do %>
          <p class="text-red text-sm"><%= error %></p>
        <% end %>
      </div>

      <div class="flex flex-row">
        <div class="grow w-full" />
        <button
          type="submit"
          disabled={@loading}
          class={"
            #{if not @loading, do: "bg-purple hover:bg-light_purple", else: "bg-light_purple"}
            text-white px-4 py-2 rounded-lg font-semibold
            transition duration-200"
          }
          phx-disable-with="Submitting..."
        >
          <%= if @loading, do: "Loading...", else: @title %>
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
    if socket.assigns.loading do
      # Ignore duplicate submits while an action is already pending
      {:noreply, socket}
    else
      params =
        socket.assigns.fields
        |> Enum.reduce(%{}, fn field, acc ->
          value =
            case field.type do
              "boolean" ->
                # HTML checkboxes only send data when checked
                # So if the key is present, it's checked
                Map.has_key?(raw_params, field.name)

              "array" ->
                raw_value = Map.get(raw_params, field.name, "")

                cond do
                  is_list(raw_value) ->
                    Enum.map(raw_value, &String.trim/1) |> Enum.reject(&(&1 == ""))

                  is_binary(raw_value) ->
                    raw_value
                    |> String.split(~r/[\n,]+/, trim: true)
                    |> Enum.map(&String.trim/1)
                    |> Enum.reject(&(&1 == ""))

                  true ->
                    []
                end

              _ ->
                Map.get(raw_params, field.name)
            end

          Map.put(acc, field.name, value)
        end)

      case Validator.validate(socket.assigns.schema, params) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "modal:form:action:#{socket.assigns.client_id}", %{
            action: socket.assigns.action,
            data: params
          })

          {:noreply, assign(socket, changeset: params, errors: nil, loading: true)}

        {:error, errors} ->
          {:noreply, assign(socket, changeset: params, errors: clean_errors(errors), loading: false)}
      end
    end
  end

  defp array_to_text(value) when is_list(value), do: Enum.join(value, "\n")
  defp array_to_text(value) when is_binary(value), do: value
  defp array_to_text(_), do: ""

  #
  # Validation error output
  #
  defp clean_errors(errors) do
    Enum.map(errors, fn {field, msg} ->
      "#{msg |> String.replace("#/", "") |> String.capitalize()} :: #{field}"
    end)
  end
end

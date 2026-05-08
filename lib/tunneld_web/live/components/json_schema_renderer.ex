defmodule TunneldWeb.Live.Components.JsonSchemaRenderer do
  @moduledoc """
  A Phoenix LiveComponent that dynamically renders forms based on JSON Schema.
  """
  use Phoenix.LiveComponent
  alias ExJsonSchema.Validator
  alias ExJsonSchema.Schema

  alias TunneldWeb.Icons

  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    schema = Schema.resolve(assigns.schema)
    client_id = Map.get(assigns, :client_id, nil)

    title = Map.get(assigns, :title, "Submit")
    values = Map.get(assigns, :values, %{})
    loading = Map.get(assigns, :loading, false)
    existing_changeset = Map.get(socket.assigns, :changeset, %{})

    ui_order = Map.get(assigns.schema, "ui:order", assigns.schema["properties"] |> Map.keys())

    fields =
      ui_order
      |> Enum.map(fn key ->
        props = Map.get(assigns.schema["properties"], key, "")

        %{
          name: key,
          type: props["type"],
          description: props["description"],
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
     |> assign(changeset: changeset)
     |> assign(client_id: client_id)
     |> assign(errors: nil)}
  end

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <form phx-target={@myself} phx-submit="submit">
      <%= for field <- @fields do %>
        <div class="mb-4">
          <% hidden = if field.hidden, do: "hidden", else: "" %>

          <label class={"#{hidden} text-text-secondary text-sm font-medium mb-1 capitalize block"}>
            <%= field.name %>
          </label>
          <label
            :if={field.description}
            class={"#{hidden} block text-text-tertiary text-xs mb-1"}
          >
            <%= field.description %>
          </label>

          <%= if is_list(field.enum) do %>
            <%= if field.type == "array" do %>
              <textarea
                name={"form[#{field.name}]"}
                rows="5"
                class={"#{hidden} tunl-input font-mono min-h-[6rem]"}
                readonly={field.readonly}
              ><%= array_to_text(Map.get(@changeset, field.name, field.default || [])) %></textarea>
              <div :if={field.help} class="bg-accent/10 py-2 px-3 rounded-md my-2 text-xs text-accent">
                <%= field.help %>
              </div>
            <% else %>
              <select
                name={"form[#{field.name}]"}
                class={"#{hidden} tunl-input"}
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
                class={"#{hidden} rounded border-border bg-bg text-accent focus:ring-accent"}
              />
            <% else %>
              <%= if field.type == "array" do %>
                <textarea
                  name={"form[#{field.name}]"}
                  rows="5"
                  class={"#{hidden} tunl-input font-mono min-h-[6rem]"}
                  readonly={field.readonly}
                ><%= array_to_text(Map.get(@changeset, field.name, field.default || [])) %></textarea>
                <div :if={field.help} class="bg-accent/10 py-2 px-3 rounded-md my-2 text-xs text-accent">
                  <%= field.help %>
                </div>
              <% else %>
                <%= if field.widget == "textarea" do %>
                  <textarea
                    name={"form[#{field.name}]"}
                    rows="6"
                    class={"#{hidden} tunl-input font-mono min-h-[6rem]"}
                    readonly={field.readonly}
                  ><%= Map.get(@changeset, field.name, field.default || "") %></textarea>
                <% else %>
                  <% input_type = if field.format == "password", do: "password", else: "text" %>
                  <input
                    type={input_type}
                    name={"form[#{field.name}]"}
                    value={Map.get(@changeset, field.name, field.default || "")}
                    class={"#{hidden} tunl-input"}
                    readonly={field.readonly}
                  />
                  <div :if={field.help} class="bg-accent/10 py-2 px-3 rounded-md my-2 text-xs text-accent">
                    <%= field.help %>
                  </div>
                <% end %>
              <% end %>
            <% end %>
          <% end %>
        </div>
      <% end %>

      <div :if={@errors} class="bg-red/10 p-3 rounded-lg mb-4">
        <%= for error <- @errors do %>
          <p class="text-red text-sm"><%= error %></p>
        <% end %>
      </div>

      <div class="flex flex-row pt-2">
        <div class="grow w-full" />
        <button
          type="submit"
          disabled={@loading}
          class="btn-primary disabled:opacity-50 disabled:cursor-not-allowed"
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
      {:noreply, socket}
    else
      params =
        socket.assigns.fields
        |> Enum.reduce(%{}, fn field, acc ->
          value =
            case field.type do
              "boolean" ->
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

  defp clean_errors(errors) do
    Enum.map(errors, fn {field, msg} ->
      "#{msg |> String.replace("#/", "") |> String.capitalize()} :: #{field}"
    end)
  end
end

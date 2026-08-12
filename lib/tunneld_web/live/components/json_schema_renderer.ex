defmodule TunneldWeb.Live.Components.JsonSchemaRenderer do
  @moduledoc """
  A Phoenix LiveComponent that dynamically renders forms based on JSON Schema.
  """
  use Phoenix.LiveComponent
  alias ExJsonSchema.Validator
  alias ExJsonSchema.Schema

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
          enum: props["ui:enum"] || if(props["type"] == "array", do: nil, else: props["enum"]),
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
          <label :if={field.description} class={"#{hidden} block text-text-tertiary text-xs mb-1"}>
            <%= field.description %>
          </label>

          <%= if is_list(field.enum) do %>
            <%= if field.type == "array" do %>
              <% chosen = List.wrap(Map.get(@changeset, field.name, field.default || [])) %>
              <!-- A real dropdown, not a listbox: <select multiple> renders as an
                   always-open scroll box and needs ctrl-click to multi-select,
                   which nobody discovers. <details> gives click-to-open with
                   plain checkboxes and no JavaScript. -->
              <details class={"#{hidden} group relative"}>
                <summary class="tunl-input flex items-center justify-between cursor-pointer list-none marker:hidden">
                  <span class="truncate">
                    <%= case length(chosen) do
                      0 -> "None selected"
                      1 -> "1 selected"
                      n -> "#{n} selected"
                    end %>
                  </span>
                  <span class="hero-chevron-down h-4 w-4 shrink-0 opacity-60 group-open:rotate-180 transition-transform">
                  </span>
                </summary>
                <div class="mt-1 max-h-56 overflow-y-auto rounded-md border border-border bg-surface p-1">
                  <label
                    :for={option <- field.enum}
                    class="group flex items-center gap-2.5 px-2 py-1.5 rounded hover:bg-surface-2 cursor-pointer text-sm select-none"
                  >
                    <% {value, label} = enum_option(option) %>
                    <!-- The native checkbox is kept for semantics and form
                         submission but visually replaced: `accent-color` cannot
                         match the rest of the panel on its own. -->
                    <input
                      type="checkbox"
                      name={"form[#{field.name}][]"}
                      value={value}
                      checked={value in chosen}
                      class="peer sr-only"
                    />
                    <!-- `peer-checked:` is a sibling selector, so it cannot reach
                         the svg nested inside this span - hence the [&>svg]
                         arbitrary variant rather than a class on the svg. -->
                    <span class="h-[15px] w-[15px] shrink-0 rounded-[4px] border border-border bg-bg flex items-center justify-center transition-colors peer-checked:bg-accent peer-checked:border-accent peer-focus-visible:ring-2 peer-focus-visible:ring-accent/50 [&>svg]:opacity-0 peer-checked:[&>svg]:opacity-100">
                      <svg viewBox="0 0 12 12" fill="none" class="h-2.5 w-2.5 transition-opacity">
                        <path
                          d="M1.5 6.2 4.4 9l6-6.4"
                          stroke="#0B0A14"
                          stroke-width="2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        />
                      </svg>
                    </span>
                    <span class="truncate text-text-secondary group-hover:text-text-primary peer-checked:text-text-primary">
                      <%= label %>
                    </span>
                  </label>
                  <p :if={field.enum == []} class="px-2 py-1.5 text-xs text-text-tertiary italic">
                    Nothing to choose from yet.
                  </p>
                </div>
              </details>
              <div :if={field.help} class="bg-accent/10 py-2 px-3 rounded-md my-2 text-xs text-accent">
                <%= field.help %>
              </div>
            <% else %>
              <% current_value = Map.get(@changeset, field.name, field.default || "") %>
              <% has_custom = "custom" in (field.enum || []) %>
              <select
                name={"form[#{field.name}]"}
                class={"#{hidden} tunl-input"}
                phx-change={if has_custom, do: "field_change", else: nil}
                phx-target={if has_custom, do: @myself, else: nil}
              >
                <%= for option <- field.enum do %>
                  <% {value, label} = enum_option(option) %>
                  <option value={value} selected={current_value == value}>
                    <%= label %>
                  </option>
                <% end %>
              </select>
              <%= if has_custom and current_value == "custom" do %>
                <input
                  type="text"
                  name={"form[#{field.name}_custom]"}
                  value={Map.get(@changeset, "#{field.name}_custom", "")}
                  placeholder="e.g. ubuntu/24.04"
                  class="tunl-input mt-2"
                />
              <% end %>
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
                <div
                  :if={field.help}
                  class="bg-accent/10 py-2 px-3 rounded-md my-2 text-xs text-accent"
                >
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
                  <div
                    :if={field.help}
                    class="bg-accent/10 py-2 px-3 rounded-md my-2 text-xs text-accent"
                  >
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

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("field_change", %{"form" => raw_params}, socket) do
    field_names = Enum.map(socket.assigns.fields, & &1.name)

    changeset =
      Enum.reduce(raw_params, socket.assigns.changeset, fn {k, v}, acc ->
        if k in field_names, do: Map.put(acc, k, v), else: acc
      end)

    {:noreply, assign(socket, changeset: changeset, errors: nil)}
  end

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

              "integer" ->
                parse_int(Map.get(raw_params, field.name))

              "number" ->
                parse_float(Map.get(raw_params, field.name))

              _ ->
                Map.get(raw_params, field.name)
            end

          # If the field is a "custom" enum option, substitute the typed value.
          value =
            if value == "custom" do
              custom = Map.get(raw_params, "#{field.name}_custom", "")

              if custom == "", do: value, else: custom
            else
              value
            end

          Map.put(acc, field.name, value)
        end)

      case Validator.validate(socket.assigns.schema, params) do
        :ok ->
          Phoenix.PubSub.broadcast(
            Tunneld.PubSub,
            "modal:form:action:#{socket.assigns.client_id}",
            %{
              action: socket.assigns.action,
              data: params
            }
          )

          {:noreply, assign(socket, changeset: params, errors: nil, loading: true)}

        {:error, errors} ->
          {:noreply,
           assign(socket, changeset: params, errors: clean_errors(errors), loading: false)}
      end
    end
  end

  # An enum entry is either a bare string (label == value) or
  # `%{"value" => v, "label" => l}`. The second form exists because a select
  # whose options are UUIDs is unusable - you cannot pick the right machine out
  # of four identical-looking ids.
  defp enum_option(%{"value" => value, "label" => label}), do: {value, label}
  defp enum_option(%{value: value, label: label}), do: {value, label}
  defp enum_option(option), do: {option, option}

  defp array_to_text(value) when is_list(value), do: Enum.join(value, "\n")
  defp array_to_text(value) when is_binary(value), do: value
  defp array_to_text(_), do: ""

  defp parse_int(nil), do: nil
  defp parse_int(s) when is_integer(s), do: s

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> s
    end
  end

  defp parse_int(_), do: nil

  defp parse_float(nil), do: nil
  defp parse_float(s) when is_number(s), do: s

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {n, ""} -> n
      _ -> s
    end
  end

  defp parse_float(_), do: nil

  defp clean_errors(errors) do
    Enum.map(errors, fn {field, msg} ->
      "#{msg |> String.replace("#/", "") |> String.capitalize()} :: #{field}"
    end)
  end
end

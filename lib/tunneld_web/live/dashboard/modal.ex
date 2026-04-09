defmodule TunneldWeb.Live.Dashboard.Modal do
  @moduledoc """
  Helpers for managing the dashboard modal state.

  The modal is a map in socket assigns with keys:
  - `show` — boolean
  - `title` — string or nil
  - `description` — string or nil
  - `body` — map (schema form data or info text)
  - `actions` — map or nil (action payload for confirmation)
  - `type` — atom (:default)

  All functions return updated socket assigns maps suitable for `assign/2`.
  """

  @default %{
    show: false,
    title: nil,
    description: nil,
    body: %{},
    actions: nil,
    type: :default
  }

  @doc "Returns the default modal state."
  def default, do: @default

  @doc "Open a modal with the given fields merged over the defaults."
  def open(fields) when is_map(fields) do
    Map.merge(@default, Map.put(fields, :show, true))
  end

  @doc "Close the modal and reset to defaults."
  def close, do: @default

  @doc "Returns true if the modal body contains a schema form."
  def schema_form?(socket_assigns) do
    socket_assigns
    |> Map.get(:modal, %{})
    |> Map.get(:body, %{})
    |> case do
      %{"type" => "schema"} -> true
      _ -> false
    end
  end
end
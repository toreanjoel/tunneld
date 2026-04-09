defmodule TunneldWeb.Live.Dashboard.Sidebar do
  @moduledoc """
  Helpers for managing the dashboard sidebar state.

  The sidebar is a map in socket assigns with keys:
  - `is_open` — boolean
  - `view` — atom or nil (:resource, :wlan, :zrok, :chat, etc.)
  - `selection` — map or nil (currently selected item details)
  """

  @default %{
    is_open: false,
    view: nil,
    selection: nil
  }

  @doc "Returns the default sidebar state."
  def default, do: @default

  @doc "Open the sidebar to a specific view, with optional selection."
  def open(view, selection \\ nil) when is_atom(view) do
    %{is_open: true, view: view, selection: selection}
  end

  @doc "Close the sidebar but preserve the view (for re-opening to same view)."
  def close(sidebar) when is_map(sidebar) do
    %{is_open: false, view: Map.get(sidebar, :view), selection: nil}
  end

  @doc "Close the sidebar completely."
  def close_all, do: @default
end
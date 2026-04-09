defmodule Tunneld.PubSub.Messages do
  @moduledoc """
  Consistent PubSub message builders for Tunneld.

  All messages in the system fall into three categories:

  - **Component updates** — sent to live components via `send_update/2`
  - **Notifications** — user-facing flash messages (info/error)
  - **Status** — system status changes (e.g., internet connectivity)

  Using these builders ensures message shapes are consistent across
  the codebase and makes it easy to add fields or change formats later.
  """

  @doc "Build a component update message for `send_update/2` routing."
  def component(id, module, data) do
    %{id: id, module: module, data: data}
  end

  @doc "Build a user notification message (displayed as flash)."
  def notification(type, message) when type in [:info, :error] do
    %{type: type, message: message}
  end

  @doc "Build an internet status message."
  def internet_status(connected?) do
    %{type: :internet, status: connected?}
  end

  @doc "Build a show_details message (opens sidebar)."
  def show_details(id, type) do
    {:show_details, %{"id" => id, "type" => type}}
  end
end
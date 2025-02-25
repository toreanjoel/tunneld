defmodule SentinelWeb.Live.Components.Modal do
  @moduledoc """
  Modal component that will be responsible for rendering the modal data and handleing the actions
  """
  use SentinelWeb, :live_component

  # Define attributes with default values and types
  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :action_title, :string, required: true
  attr :action, :map, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-secondary bg-opacity-80 flex items-center justify-center">
      <div class="bg-primary rounded-md p-6 w-1/3">
        <h2 class="text-2xl"><%= @title %></h2>
        <p class="my-2 text-sm"><%= @body %></p>
        <div class="py-2" />
        <div class="flex justify-end space-x-3">
          <div class="flex w-full justify-end gap-4 mt-4">
            <button
              phx-click="close_modal"
              class="text-sm font-light gap-1 bg-secondary hover:bg-opacity-60 p-3 cursor-pointer rounded-md"
            >
              Cancel
            </button>

            <button
              phx-click="execute_modal_action"
              phx-value-type={@action["type"]}
              phx-value-data={Jason.encode!(@action["data"])}
              class="text-sm font-light gap-1 bg-purple hover:bg-opacity-60 p-3 cursor-pointer rounded-md"
            >
              <%= @action_title %>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

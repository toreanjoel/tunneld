defmodule SentinelWeb.Live.Components.Modal do
  use SentinelWeb, :live_component

  attr :title, :string, required: true
  attr :body, :any, required: true  # Can be a string or a module function
  attr :action_title, :string, required: false
  attr :action, :map, required: false
  attr :show_actions, :boolean, default: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-secondary bg-opacity-80 flex items-center justify-center">
      <div class="bg-primary rounded-md p-6 w-1/3">
        <h2 class="text-2xl"><%= @title %></h2>

        <!-- Render the dynamic body -->
        <%= @body %>

        <!-- Modal Actions -->
        <%= if @show_actions do %>
          <div class="flex justify-end space-x-3">
            <button phx-click="close_modal" class="text-sm font-light gap-1 bg-secondary hover:bg-opacity-60 p-3 cursor-pointer rounded-md">
              Cancel
            </button>

            <button
              :if={@action_title}
              phx-click="execute_modal_action"
              phx-value-type={@action["type"]}
              phx-value-data={Jason.encode!(@action["data"])}
              class="text-sm font-light gap-1 bg-purple hover:bg-opacity-60 p-3 cursor-pointer rounded-md"
            >
              <%= @action_title %>
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end

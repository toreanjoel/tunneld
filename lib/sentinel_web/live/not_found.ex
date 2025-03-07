defmodule SentinelWeb.Live.NotFound do
  @moduledoc """
    This will render the not found page for non-existing routes
  """
  use SentinelWeb, :live_view
  alias SentinelWeb.Router.Helpers, as: Routes

  @doc """
  Rendering the not found markup page
  """
  def render(assigns) do
    ~H"""
    <div class="h-screen bg-primary flex flex-col items-center justify-center">
        <p class="text-2xl font-bold text-gray-1">Page Not Found</p>
        <button class="mt-4 px-3 py-2 rounded-md font-bold text-white hover:bg-light_purple bg-purple" phx-click="go_back">
          Back
        </button>
    </div>
    """
  end

  # Redirect the user to the login page
  def handle_event("go_back", _, socket) do
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
  end
end

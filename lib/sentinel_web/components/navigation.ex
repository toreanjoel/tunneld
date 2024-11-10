defmodule SentinelWeb.Components.Navigation do
  @moduledoc """
  The basic navigation component that will be wrapped around pages.
  This will be a basic stateless component
  """
  use Phoenix.Component
  import SentinelWeb.CoreComponents

  attr :id, :string, required: true
  slot :inner_block, required: true

  @doc """
  Show the navigation
  """
  def show(assigns) do
    ~H"""
    <!-- NOTE: make a component that has the navigation -->
    <div id={@id} class="flex flex-row lg:flex-row min-h-screen sm:height-screen">
      <!-- Navigation -->
      <div class="min-w-[50px] flex flex-col items-center py-3 border-r border-zinc-300">
        <!-- Navigation Icons with Hover Effect -->
        <div class="flex flex-col text-black">
          <div class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500 transition-all duration-500">
            <.icon name="hero-home" class="h-5 w-5" />
          </div>
          <div class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-no-symbol" class="h-5 w-5" />
          </div>
          <div class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-device-phone-mobile" class="h-5 w-5" />
          </div>
        </div>
        <!-- Spacer -->
        <div class="grow" />
        <!-- Settings Icons with Hover Effect -->
        <div class="flex flex-col text-black">
          <div class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-cog" class="h-5 w-5" />
          </div>

          <%!-- Logout --%>
          <div phx-click="logout" class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-arrow-right-end-on-rectangle" class="h-5 w-5" />
          </div>
        </div>

        <span class="text-[10px] text-gray-500 pt-3">
          v: <%= Application.get_env(:sentinel, :version) %>
        </span>
      </div>
      <!-- Main section -->
      <div class="flex flex-col grow items-center justify-center w-full lg:w-3/5 p-8 max-w-[767px] mx-auto">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
end

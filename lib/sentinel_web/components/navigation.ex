defmodule SentinelWeb.Components.Navigation do
  @moduledoc """
  The basic navigation component that will be wrapped around pages.
  """
  use Phoenix.Component
  import SentinelWeb.CoreComponents

  attr :id, :string, required: true
  attr :align, :string, default: "center"
  attr :justify, :string, default: "center"
  slot :inner_block, required: true

  @doc """
  Show the navigation.
  """
  def show(assigns) do
    ~H"""
    <div id={@id} class="flex flex-row min-h-screen">
      <!-- Fixed Navigation -->
      <div class="fixed h-screen w-[50px] flex flex-col items-center py-3 border-r border-zinc-300 bg-gray-100">
        <!-- Navigation Icons with Hover Effect -->
        <div class="flex flex-col text-black">
          <.link navigate="/dashboard" class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-home" class="h-5 w-5" />
          </.link>
          <.link navigate="/blacklist" class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-no-symbol" class="h-5 w-5" />
          </.link>
          <.link navigate="/devices" class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-device-phone-mobile" class="h-5 w-5" />
          </.link>
          <.link navigate="/logs" class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-briefcase" class="h-5 w-5" />
          </.link>
        </div>
        <!-- Spacer -->
        <div class="grow" />
        <!-- Settings Icons with Hover Effect -->
        <div class="flex flex-col text-black">
          <.link navigate="/settings" class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-cog" class="h-5 w-5" />
          </.link>
          <!-- Logout -->
          <div phx-click="logout" class="cursor-pointer hover:bg-white hover:rounded-lg p-2 transition-all duration-500">
            <.icon name="hero-arrow-right-end-on-rectangle" class="h-5 w-5" />
          </div>
        </div>
        <span class="text-[10px] text-gray-500 pt-3">
          v: <%= Application.get_env(:sentinel, :version) %>
        </span>
      </div>

      <!-- Centered, scrollable main section -->
      <div class={"flex grow items-#{@align} md:items-#{@align} justify-#{@justify} ml-[50px] overflow-y-auto"}>
        <div class={"flex flex-col items-#{@align} w-full p-8"}>
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

end

defmodule TunneldWeb.Live.Components.SettingsDropdown do
  @moduledoc """
  Settings dropdown menu: Authentication, DNS Server, Restart Device.
  """
  use Phoenix.Component
  import TunneldWeb.Icons

  attr :open, :boolean, default: false

  def settings_dropdown(assigns) do
    ~H"""
    <div
      :if={@open}
      phx-click-away="close_settings_menu"
      class="absolute right-0 top-full mt-1 w-48 bg-surface rounded-lg shadow-lg z-50 py-1 border border-border"
    >
      <div phx-click="open_settings" phx-value-type="authentication" class="menu-item">
        <.settings size={14} /> Authentication
      </div>
      <div class="border-t border-border my-1" />
      <div phx-click="logout" class="menu-item">
        <.log_out size={14} /> Log out
      </div>
      <div phx-click="restart_device" class="menu-item !text-red">
        <.refresh size={14} /> Restart Device
      </div>
    </div>
    """
  end
end

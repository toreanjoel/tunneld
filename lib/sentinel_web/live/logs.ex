defmodule SentinelWeb.Live.Logs do
  @moduledoc """
  Logs Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Logs}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  @doc """
  The list of log backups
  """
  def mount(_params, _session, socket) do
    SentinelWeb.Endpoint.subscribe("sentinel:logs")

    socket =
      socket
      |> assign(:archived_files, [])
      |> assign(:count, 0)

    send(self(), :init)
    {:ok, socket}
  end

  @doc """
  Render the Devices
  """
  def render(assigns) do
    ~H"""
    <Navigation.show id="nav" align="start">
      <div class="text-left w-full">
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Log Archive
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 text-sm text-gray-600">
          The archived list of logs (note logs will be available only for 7 days)
        </div>
        <hr class="my-3 border-dashed border-gray-300" />

        <p :if={@count == 0} class="text-gray-500">No Logs Archived</p>
        <div :if={@count > 0} class="overflow-x-auto">
          <table class="table-auto border-collapse border border-gray-200 w-full">
            <thead>
              <tr class="bg-gray-100">
                <th class="border border-gray-300 px-4 py-2 text-left">Name</th>
                <th class="border border-gray-300 px-4 py-2 text-left w-2">Action</th>
              </tr>
            </thead>
            <tbody>
              <%= for log_file <- @archived_files do %>
                <tr
                  class={"#{if log_file === "dnsmasq.log", do: "bg-gray-200 text-gray-500", else: "hover:bg-gray-50 cursor-pointer"}"}
                  phx-click={if log_file !== "dnsmasq.log", do: "navigate", else: nil}
                  phx-value-name={if log_file !== "dnsmasq.log", do: log_file, else: nil}
                >
                  <td class="border border-gray-300 px-4 py-2"><%= log_file %></td>
                  <td class="border border-gray-300 px-4 py-2" :if={log_file !== "dnsmasq.log"}>
                    <div class="flex flex-row gap-2">
                    <div class="bg-white hover:bg-gray-200 p-1 rounded">
                      <.icon name="hero-no-symbol" class="h-5 w-5" />
                    </div>
                    <div class="bg-white hover:bg-gray-200 p-1 rounded">
                      <.icon name="hero-arrow-down-tray" class="h-5 w-5" />
                    </div>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </Navigation.show>
    """
  end

  @doc """
  Handle form validation on input change
  TODO: move this to the nav component
  """
  def handle_event("logout", _, socket) do
    # TODO: we need to consider doing a modal over here
    Session.delete(socket.assigns.ip)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
  end

  # get the devices for the current devices connect
  def handle_info(:init, socket) do
    {_, data} = Logs.get_state()

    socket =
      socket
      |> assign(:archived_files, data.archived.files)
      |> assign(:count, data.archived.count)

    {:noreply, socket}
  end

  # The general updates from polling system data
  def handle_info({:archived_files, archived}, socket) do
    socket =
      socket
      |> assign(:archived_files, archived.files)
      |> assign(:count, archived.count)

    {:noreply, socket}
  end
end

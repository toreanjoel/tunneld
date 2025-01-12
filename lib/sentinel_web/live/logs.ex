defmodule SentinelWeb.Live.Logs do
  @moduledoc """
  Logs Page
  """
  use SentinelWeb, :live_view
  import SentinelWeb.CoreComponents
  alias Sentinel.Servers.{Session, Logs}
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  # The current active file used for the running process
  @active_log_file "_data.log"

  @doc """
  The list of log backups
  """
  def mount(_params, _session, socket) do
    SentinelWeb.Endpoint.subscribe("sentinel:logs")

    socket =
      socket
      |> assign(:archived_files, [])
      |> assign(:count, 0)
      |> assign(modal: %{show: false, type: nil})
      |> assign(:active_log_file, @active_log_file)

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
        <div class="py-1 text-sm text-gray-600 flex flex-row items-center">
        <div class="grow">
          The archived list of logs (Logs will be available only for 7 days. All logs will be deleted after.)
        </div>
        <div phx-click="refresh" class="cursor-pointer hover:bg-white p-1 hover:rounded-lg transition-all duration-500">
            <.icon name="hero-arrow-path" class="h-5 w-5" />
          </div>
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
                  class={"#{if log_file === @active_log_file, do: "bg-gray-200 text-gray-500", else: ""}"}
                  phx-value-name={if log_file !== @active_log_file, do: log_file, else: nil}
                >
                  <td class="border border-gray-300 px-4 py-2">
                  <%= log_file %> <%= if log_file === @active_log_file, do: "(active)" %>
                  </td>
                  <td class="border border-gray-300 px-4 py-2">
                    <div class="flex flex-row gap-2">
                      <a
                        href={Routes.file_download_path(@socket, :download, log_file)}
                        class="bg-white hover:bg-gray-200 p-1 rounded cursor-pointer"
                      >
                        <.icon name="hero-arrow-down-tray" class="h-5 w-5" />
                      </a>
                      <div
                        :if={log_file !== @active_log_file}
                        phx-click="open_modal"
                        phx-value-file={log_file}
                        class="bg-white hover:bg-gray-200 p-1 rounded cursor-pointer"
                      >
                        <.icon name="hero-no-symbol" class="h-5 w-5" />
                      </div>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
        <!-- Modal -->
        <%= if @modal.show do %>
          <div class="fixed inset-0 z-10 flex items-center justify-center bg-black bg-opacity-50">
            <div class="bg-white rounded-lg shadow-lg p-6 w-full max-w-md">
              <%= render_modal(@modal.type, assigns) %>
            </div>
          </div>
        <% end %>
      </div>
    </Navigation.show>
    """
  end

  @doc """
  Handle form validation on input change
  """
  def handle_event("logout", _, socket) do
    # TODO: we need to consider doing a modal over here
    Session.delete(socket.assigns.ip)
    {:noreply, socket |> push_navigate(to: Routes.live_path(socket, SentinelWeb.Live.Login))}
  end

  # Delete the file
  def handle_event("delete", %{"file" => file}, socket) do
    case Logs.delete_log_file(file) do
      {:ok, _} ->
        Logs.init_state()
        {:noreply, assign(socket, modal: %{show: false, type: nil, file: nil})}

      {:error, reason} ->
        IO.inspect("Error: #{reason}")
        {:noreply, assign(socket, modal: %{show: false, type: nil, file: nil})}
    end
  end

  # Open the modal
  def handle_event("open_modal", %{"file" => file}, socket) do
    {:noreply, assign(socket, modal: %{show: true, type: :confirm_removal, file: file})}
  end

  # Close the modal
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: %{show: false, type: nil, file: nil})}
  end

  # refresh the lists
  def handle_event("refresh", _p, socket) do
    send(self(), :init)
    {:noreply, socket}
  end

  # get the devices for the current devices connect
  def handle_info(:init, socket) do
    {_, data} = Logs.init_state()

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

  # Render the modal content
  defp render_modal(:confirm_removal, assigns) do
    ~H"""
    <div class="flex flex-col w-full gap-3">
      <h2 class="text-2xl font-bold">Are you sure?</h2>
      <div class="w-full">
        <span class="text-xs text-gray-500 leading-0">
          Are you sure you want to remove this file <%= @modal.file %>?
        </span>
      </div>
      <!-- Action Buttons -->
      <div class="flex w-full justify-end gap-4 mt-3">
        <.button
          phx-click="delete"
          phx-value-file={@modal.file}
          class="bg-blue-500 text-white px-4 py-2 rounded-md"
        >
          Delete
        </.button>
        <.button phx-click="close_modal" class="bg-red-500 text-white px-4 py-2 rounded-md">
          Cancel
        </.button>
      </div>
    </div>
    """
  end
end

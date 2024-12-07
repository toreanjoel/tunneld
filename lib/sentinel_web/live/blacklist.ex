defmodule SentinelWeb.Live.Blacklist do
  @moduledoc """
  Blacklist Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Blacklist}
  alias Sentinel.Schema.Blacklist, as: BlacklistSchema
  alias SentinelWeb.Components.Navigation
  alias SentinelWeb.Router.Helpers, as: Routes

  # we check if the user is authenticated
  on_mount SentinelWeb.Hooks.CheckAuth

  # The size of the page we want to retrieve
  @page_size 2

  @doc """
  Initialize the Blacklist
  """
  def mount(_params, %{"ip" => ip} = _session, socket) do
    blacklist_changeset =
      BlacklistSchema.changeset(%BlacklistSchema{}, %{})

    # connect to the system broadcast channel topic
    SentinelWeb.Endpoint.subscribe("sentinel:blacklist")

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(:blacklist, [])
      |> assign(:has_more_data, false)
      |> assign(:curr_page, 0)
      |> assign(:count, 0)
      |> assign(blacklist_changeset: blacklist_changeset)
      |> assign(modal: %{show: false, type: nil})
      |> assign(errors: [])

    send(self(), :init)

    {:ok, socket}
  end

  @doc """
  Render the Blacklist
  """
  def render(assigns) do
    ~H"""
    <Navigation.show id="nav" align="start">
      <div class="text-left">
        <div class="text-3xl md:text-5xl py-2 font-bold bg-gradient-to-r from-gray-700 to-gray-300 bg-clip-text text-transparent">
          Blacklist
        </div>
        <%!-- This will be the basic text information that could be informational but some insights --%>
        <div class="py-1 text-sm text-gray-600 flex flex-row items-center">
          <div class="grow">
            List of domains that are blocked from being accessed
          </div>
          <div
            phx-click="open_modal"
            class="cursor-pointer hover:bg-white p-1 hover:rounded-lg transition-all duration-500"
          >
            <.icon name="hero-plus-circle" class="h-5 w-5" />
          </div>
        </div>

        <hr class="my-3 border-dashed border-gray-300" />

        <p :if={@count == 0}>No domains blocked</p>
        <div :if={@count > 0} class="overflow-x-auto">
          <table class="table-auto border-collapse border border-gray-200 w-full">
            <thead>
              <tr class="bg-gray-100">
                <th class="border border-gray-300 px-4 py-2 text-left">Domain</th>
              </tr>
            </thead>
            <tbody>
              <%= for domain <- @blacklist do %>
                <tr class="hover:bg-gray-50 cursor-pointer">
                  <td class="border border-gray-300 px-4 py-2"><%= domain %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="py-2 flex flex-row justify-between">
          <button
            disabled={@curr_page == 0}
            phx-click="prev_page"
            class="bg-zinc-900 hover:bg-zinc-700 text-white font-bold py-2 px-4 rounded"
          >
            Prev
          </button>
          <button
            :if={@has_more_data}
            phx-click="next_page"
            class="bg-zinc-900 hover:bg-zinc-700 text-white font-bold py-2 px-4 rounded ml-2"
          >
            Next
          </button>
        </div>
      </div>
      <!-- Modal -->
      <%= if @modal.show do %>
        <div class="fixed inset-0 z-10 flex items-center justify-center bg-black bg-opacity-50">
          <div class="bg-white rounded-lg shadow-lg p-6 w-full max-w-md">
            <%= render_modal(@modal.type, assigns) %>
          </div>
        </div>
      <% end %>
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

  # Next and prev pages
  def handle_event("prev_page", _, socket) do
    curr_page =
      if socket.assigns.curr_page > 0, do: socket.assigns.curr_page - @page_size, else: 0

    {_, blacklist} = Blacklist.get_blacklist_page(curr_page, @page_size)

    socket =
      socket
      |> assign(:blacklist, blacklist.data)
      |> assign(:has_more_data, blacklist.has_more_data)
      |> assign(:curr_page, blacklist.curr_page)

    {:noreply, socket}
  end

  def handle_event("next_page", _, socket) do
    curr_page = socket.assigns.curr_page
    {_, blacklist} = Blacklist.get_blacklist_page(curr_page + @page_size, @page_size)

    socket =
      socket
      |> assign(:blacklist, blacklist.data)
      |> assign(:has_more_data, blacklist.has_more_data)
      |> assign(:curr_page, blacklist.curr_page)

    {:noreply, socket}
  end

  # Open the modal
  def handle_event("open_modal", _params, socket) do
    {:noreply, assign(socket, modal: %{show: true, type: :add_domain})}
  end

  # Close the modal
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: %{show: false, type: nil})}
  end

  # Add a domain to the blacklist
  def handle_event("add_domain", params, socket) do
    changeset = BlacklistSchema.changeset(%BlacklistSchema{}, params)
    case changeset.valid? do
      true ->
        # TODO: Write domain to file

        # TODO: Restart the blacklist service

        # TODO: Fetch the blacklist current page again

        # Add success flash message
        socket =
          socket
          |> put_flash(:info, "Domain added successfully!")
          # Close modal
          |> assign(modal: %{show: false, type: nil})

        {:noreply, socket}

      _ ->
        # Add error flash message and reassign changeset
        errors = Enum.map(changeset.errors, fn {field, {msg, _}} -> "#{field} #{msg}" end)

        socket =
          socket
          |> assign(:errors, errors)
          |> assign(blacklist_changeset: changeset)

        {:noreply, socket}
    end
  end

  # get the blacklist for the current blacklist connect
  def handle_info(:init, socket) do
    {_, blacklist_state} = Blacklist.get_state()
    {_, blacklist} = Blacklist.get_blacklist_page(0, @page_size)

    socket =
      socket
      |> assign(:blacklist, blacklist.data)
      |> assign(:has_more_data, blacklist.has_more_data)
      |> assign(:curr_page, blacklist.curr_page)
      |> assign(:count, blacklist_state.count)

    {:noreply, socket}
  end

  # The general updates from polling system data
  def handle_info({:blacklist_info, msg}, socket) do
    socket =
      socket
      |> assign(:count, msg.count)

    {:noreply, socket}
  end

  # Render the modal content
  defp render_modal(:add_domain, assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center w-full gap-3">
      <h2 class="text-2xl font-bold text-center">Add Domain</h2>
      <.simple_form for={@blacklist_changeset} phx-submit="add_domain" class="w-full max-w-md">
        <div class="w-full">
          <.input
            label="Url"
            name="domain"
            id="domain"
            type="text"
            value={@blacklist_changeset.changes[:domain] || ""}
            class="mt-2 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
          />
          <span class="text-xs text-gray-500 leading-0">
            Domain that you want to block across all devices on the network
          </span>
        </div>
        <!-- Error Messages -->
        <div class="text-xs text-red-600">
          <%= for error <- @errors do %>
            <p><%= error |> String.capitalize() %></p>
          <% end %>
        </div>
        <!-- Action Buttons -->
        <div class="flex w-full justify-end gap-4 mt-3">
          <.button type="submit" class="bg-blue-500 text-white px-4 py-2 rounded-md">
            Add
          </.button>
          <.button phx-click="close_modal" class="bg-red-500 text-white px-4 py-2 rounded-md">
            Close
          </.button>
        </div>
      </.simple_form>
    </div>
    """
  end
end

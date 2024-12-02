defmodule SentinelWeb.Live.Blacklist do
  @moduledoc """
  Blacklist Page
  """
  use SentinelWeb, :live_view
  alias Sentinel.Servers.{Session, Blacklist}
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
    # connect to the system broadcast channel topic
    SentinelWeb.Endpoint.subscribe("sentinel:blacklist")

    socket =
      socket
      |> assign(:ip, ip)
      |> assign(:blacklist, [])
      |> assign(:has_more_data, false)
      |> assign(:curr_page, 0)
      |> assign(:count, 0)

    send(self(), :init)

    {:ok, socket}
  end

  @doc """
  Render the Blacklist
  """
  def render(assigns) do
    ~H"""
    <Navigation.show id="nav">
      <div class="text-left">
        <h2>Blacklist</h2>
        <p :if={@count == 0}>No domains blocked</p>

        <div :if={@count > 0}>
          <%= for domain <- @blacklist do %>
            <div><%= domain %></div>
          <% end %>
        </div>

        <div class="py-2 flex flex-row justify-between">
          <button
            :if={@curr_page > 0}
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
    curr_page = if socket.assigns.curr_page > 0, do: socket.assigns.curr_page - @page_size, else: 0
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
end

defmodule SentinelWeb.Live.Components.Sidebar.Details do
  @moduledoc """
  The list of sidebar details to render
  """
  use SentinelWeb, :live_component

  # To move to separate component - logs
  alias SentinelWeb.Router.Helpers, as: Routes

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "component:details")
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    view = Map.get(assigns, :view, socket.assigns[:view] || :system_overview)
    new_data = Map.get(assigns, :data, %{})


    socket =
      socket
      |> assign(view: view)
      |> assign(data: new_data)

    IO.inspect(socket)
    {:ok, socket}
  end

  @spec render(%{:view => :system_overview, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  def render(%{view: :system_overview} = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <.icon class="w-[50px] h-[50px] text-green" name="hero-shield-check" />
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">System is running as expected.</h1>
    </div>
    """
  end

  @spec render(%{:view => :node, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :node} = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">node</h1>
    </div>
    """
  end

  @spec render(%{:view => :service, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :service} = assigns) do
    data = Map.get(assigns, :data)
    logs = Map.get(data, :logs, [])

    assigns =
      assigns
      |> assign(logs: logs)

    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <p :if={@logs |> length == 0} class="text-gray-500">No Service Logs</p>
      <div :if={@logs |> length > 0} class="overflow-x-auto">
        <table class="table-auto w-full">
          <tbody>
            <%= for log <- @logs do %>
              <tr>
                <td class="px-4 py-2">
                  <%= log %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :device, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :device} = assigns) do
    data = Map.get(assigns, :data)
    logs = Map.get(data, :logs, [])

    assigns =
      assigns
      |> assign(logs: logs)

    ~H"""
    <div class="h-full flex flex-col system-scroll">
      <p :if={@logs |> length() == 0}>No Logs Archived</p>
      <table :if={!(@logs |> length() == 0)} class="table-auto border-collapse w-full">
        <thead>
          <tr>
            <th class="text-left">Time</th>
            <th class="text-left">Query Type</th>
            <th class="text-left">Domain</th>
          </tr>
        </thead>
        <tbody>
          <%= for log <- @logs do %>
            <tr>
              <td><%= log.time %></td>
              <td><%= log.query_type %></td>
              <td><%= log.domain %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  @spec render(%{:view => :blacklist, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :blacklist} = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center system-scroll h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">blacklist</h1>

      <%!-- TODO: add overflow here for content --%>
    </div>
    """
  end

  @spec render(%{:view => :logs, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :logs} = assigns) do
    data = Map.get(assigns, :data)
    logs = Map.get(data, :logs, %{})

    assigns =
      assigns
      |> assign(files: Map.get(logs, :files, []))
      |> assign(count: Map.get(logs, :count, 0))

    ~H"""
    <div class="h-full flex flex-col system-scroll">
      <div class="text-left w-full flex flex-col">
        <p :if={@count == 0}>No Logs Archived</p>
        <div :if={@count > 0} class="overflow-x-auto">
          <table class="table-auto border-collapse w-full">
            <thead>
              <tr class="bg-secondary">
                <th class="px-4 py-2 text-left">Name</th>
                <th class="px-4 py-2 text-left w-2">Action</th>
              </tr>
            </thead>
            <tbody>
              <%= for log_file <- @files do %>
                <tr phx-value-name={if log_file !== "_data.log", do: log_file, else: nil}>
                  <td class="px-4 py-2">
                    <%= log_file %> <%= if log_file === "_data.log", do: "(active)" %>
                  </td>
                  <td class="px-4 py-2">
                    <div class="flex flex-row gap-2">
                      <a
                        href={Routes.file_download_path(@socket, :download, log_file)}
                        class="cursor-pointer"
                      >
                        <.icon name="hero-arrow-down-tray" class="h-5 w-5" />
                      </a>
                      <div
                        :if={log_file !== "_data.log"}
                        phx-click="open_modal"
                        phx-value-file={log_file}
                        class="cursor-pointer"
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
      </div>
    </div>
    """
  end
end

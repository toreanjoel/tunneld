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
    <div class="h-full flex flex-col items-center justify-center p-3 h-full">
      <.icon class="w-[50px] h-[50px] text-green" name="hero-shield-check" />
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">System is running as expected.</h1>
    </div>
    """
  end

  @spec render(%{:view => :node, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :node} = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center p-3 h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">node</h1>
    </div>
    """
  end

  @spec render(%{:view => :service, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :service} = assigns) do
    data = Map.get(assigns, :data)
    logs = Map.get(data, :logs, [])
    count = length(logs)

    assigns =
      assigns
      |> assign(logs: logs)
      |> assign(count: count)

    ~H"""
    <div class="bg-secondary p-2 h-full">
      <div class={"h-full flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Service Logs
        </h1>

        <div :if={@count > 0}>
          <%= for log <- @logs do %>
            <div class="flex flex-col p-3 my-2 bg-primary rounded-lg font-light">
              <div class="text-sm"><%= log %></div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :device, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :device} = assigns) do
    data = Map.get(assigns, :data)
    logs = Map.get(data, :logs, [])
    count = length(logs)

    assigns =
      assigns
      |> assign(logs: logs)
      |> assign(count: count)

    ~H"""
    <div class="bg-secondary p-2 h-full">
      <div class={"h-full flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Device Logs
        </h1>

        <div :if={!(@count == 0)}>
          <%= for log <- @logs do %>
            <div class="flex flex-col p-3 my-2 bg-primary rounded-lg font-light">
              <div class="text-sm truncate">
                <span class="font-bold">Domain:</span> <%= log.domain %>
              </div>
              <div class="text-sm truncate"><span class="font-bold">Time:</span> <%= log.time %></div>
              <div class="text-sm truncate">
                <span class="font-bold">Query Type:</span> <%= log.query_type %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :blacklist, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :blacklist} = assigns) do
    data = Map.get(assigns, :data)
    blacklist = Map.get(data, :blacklist, [])
    count = length(blacklist)

    assigns =
      assigns
      |> assign(blacklist: blacklist)
      |> assign(count: count)

    ~H"""
    <div class="bg-secondary p-2 h-full">
      <%!-- Sidebar header that will house metadat?  --%>
      <%= sidebar_header(assigns) %>

      <div class="flex flex-row gap-1 justify-end my-2">
        <%!-- Actions to take --%>
        <div
          phx-click="open_modal"
          phx-value-modal_title="Domain to block for the entire system"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Sentinel.Schema.Blacklist.data(:system),
              "default_values" => %{}
            })
          }
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md"
        >
          <.icon class="w-4 h-4" name="hero-no-symbol" />
          <div class="truncate text-xs text-gray-1">System Block</div>
        </div>

        <div
          phx-click="open_modal"
          phx-value-modal_title="Domain to block for a user"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Sentinel.Schema.Blacklist.data(:user),
              "default_values" => %{}
            })
          }
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md"
        >
          <.icon class="w-4 h-4" name="hero-no-symbol" />
          <div class="truncate text-xs text-gray-1">Device Block</div>
        </div>
      </div>

      <div class={"h-full flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Domains Blocked
        </h1>

        <div :if={@count > 0}>
          <%= for %{"domain" => domain, "ip" => ip, "mac_addr" => mac, "ttl" => ttl, "type" => type} <- @blacklist do %>
            <div class="flex flex-col p-3 my-2 bg-primary rounded-lg font-light">
              <div class="text-sm truncate"><span class="font-bold">Domain:</span> <%= domain %></div>
              <div class="text-sm truncate"><span class="font-bold">IP:</span> <%= ip %></div>
              <div class="text-sm truncate">
                <span class="font-bold">MAC Address (USER):</span> <%= mac %>
              </div>
              <div class="text-sm truncate"><span class="font-bold">TTL:</span> <%= ttl %></div>
              <div class="text-sm truncate"><span class="font-bold">Type:</span> <%= type %></div>

              <div class="divider" />
              <div class="flex justify-end mt-2">
                <div
                  phx-click="open_modal"
                  phx-value-modal_title="Remove Domain Blocked?"
                  phx-value-modal_body={
                    Jason.encode!(%{
                      "type" => "string",
                      "data" => "Are you sure you want to remove the blocked domain?"
                    })
                  }
                  phx-value-modal_actions={
                    Jason.encode!(%{
                      "title" => "Remove",
                      "payload" => %{
                        "type" => "blocked_domain_remove",
                        "data" => %{"domain" => domain, "mac" => mac, "type" => type}
                      }
                    })
                  }
                  class="cursor-pointer text-red-500"
                >
                  <.icon name="hero-no-symbol" class="h-5 w-5" />
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
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
    <div class="bg-secondary p-2 h-full">
      <div class={"h-full flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Logs Archived
        </h1>

        <div :if={@count > 0}>
          <%= for log_file <- @files do %>
            <div class="flex flex-col p-3 my-2 bg-primary rounded-lg font-light">
              <div class="text-sm truncate">
                <span class="font-bold">Name:</span> <%= log_file %>
                <%= if log_file === "_data.log", do: "(active)" %>
              </div>

              <div class="flex justify-end mt-2 space-x-3">
                <a
                  href={Routes.file_download_path(@socket, :download, log_file)}
                  class="cursor-pointer"
                >
                  <.icon name="hero-arrow-down-tray" class="h-5 w-5" />
                </a>

                <%!-- TODO: change this so we only see this when we have files to be deleted  --%>
                <div
                  phx-click="open_modal"
                  phx-value-modal_title="Remove Archived Backup?"
                  phx-value-modal_body={
                    Jason.encode!(%{
                      "type" => "string",
                      "data" => "Are you sure you want to remove the file?"
                    })
                  }
                  phx-value-modal_actions={
                    Jason.encode!(%{
                      "title" => "Remove",
                      "payload" => %{"type" => "backup_file_delete", "data" => %{"file" => "DELETE"}}
                    })
                  }
                  class="cursor-pointer text-red-500"
                >
                  <.icon name="hero-no-symbol" class="h-5 w-5" />
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  #
  # Sidebar header componen
  # Contains information around the sidebar context, will take params but this will be specific to sidebar
  #
  defp sidebar_header(assigns) do
    ~H"""
      <div class="min-h-[200px] bg-primary bg-opacity-80 bg-gradient-to-r from-gray-2 via-light_purple to-purple rounded-md p-3">
        <div class="text-2xl font-medium">Header</div>
        <div class="text-lg">Some description comes here about the current context we are viewing of the sidebar</div>
      </div>
    """
  end
end

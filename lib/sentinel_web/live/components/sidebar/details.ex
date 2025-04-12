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

    {:ok, socket}
  end

  @spec render(%{:view => :system_overview, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  def render(%{view: :system_overview} = assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center p-3 h-full">
      <.icon class="w-[50px] h-[50px] text-green" name="hero-shield-check" />
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">System is running as expected.</h1>
    </div>
    """
  end

  @spec render(%{:view => :node, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :node} = assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center p-3 h-full">
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">node</h1>
    </div>
    """
  end

  @spec render(%{:view => :wlan, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :wlan} = assigns) do
    data = Map.get(assigns, :data)

    assigns =
      assigns
      |> assign(networks: Map.get(data, :networks, []))
      |> assign(info: Map.get(data, :info, %{}))
      |> assign(count: data |> List.wrap() |> length())

    ~H"""
    <div class="bg-secondary p-2 h-full">
      <%!-- Sidebar header that will house metadat?  --%>
      <%= sidebar_header(assigns, %{
        header: "Wireless Network Access",
        body: "Connect to wireless access points in order to get internet access to your gateway"
      }) %>

      <pre
        :if={@info["wpa_state"] !== "COMPLETED" and not Enum.empty?(@info)}
        class="bg-gray-900 text-gray-100 text-xs p-3 rounded-md overflow-auto"
      ><%= Jason.encode!(@info, pretty: true) %></pre>

      <div class="flex flex-row gap-1 justify-end my-2">
        <%!-- Actions to take --%>
        <div
          phx-click="trigger_action"
          phx-value-action="scan_for_wireless_networks"
          phx-value-data={Jason.encode!(%{})}
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md"
        >
          <.icon class="w-4 h-4" name="hero-arrow-path" />
          <div class="truncate text-xs text-gray-1">Refresh</div>
        </div>
      </div>

      <div class={"flex flex-col #{if @count== 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Wireless Networks Found
        </h1>

        <div :if={@count > 0}>
          <%= for %{ open: open, security: security, signal: signal, ssid: ssid } <- @networks do %>
            <% current_connected = @info["ssid"] === ssid %>

            <div class={"flex flex-col p-3 mb-2 #{if current_connected, do: "bg-purple", else: "bg-primary"} rounded-lg font-light"}>
              <div class="text-md truncate"><span class="font-bold">SSID:</span> <%= ssid %></div>
              <div class="text-sm truncate">
                <span class="font-bold">Security:</span> <%= security %>
              </div>
              <div class="text-sm truncate">
                <span class="font-bold">Signal:</span> <%= signal %>
              </div>
              <div class="text-sm truncate">
                <span class="font-bold">Open Network:</span> <%= open %>
              </div>

              <div class="py-2">
                <pre
                  :if={current_connected}
                  class="bg-gray-900 text-gray-100 text-xs p-3 rounded-md overflow-auto"
                ><%= Jason.encode!(@info, pretty: true) %></pre>
              </div>

              <div class="divider" />
              <div class="flex justify-end mt-2">
                <%!-- If we are connected to the network --%>
                <div
                  :if={current_connected}
                  phx-click="trigger_action"
                  phx-value-action="disconnect_from_wireless_network"
                  phx-value-data={Jason.encode!(%{})}
                  class="flex items-center justify-center gap-1 bg-secondary p-2 cursor-pointer rounded-md"
                >
                  <div class="truncate text-xs text-gray-1">disconnect</div>
                </div>

                <%!-- If we are not connected to the network --%>
                <div
                  :if={not current_connected}
                  phx-click="modal_open"
                  phx-value-modal_title="Connect to wireless network"
                  phx-value-modal_body={
                    Jason.encode!(%{
                      "type" => "schema",
                      "data" => Sentinel.Schema.Wlan.data(%{title: ssid}),
                      "default_values" => %{
                        ssid: [ssid]
                      },
                      "action" => "connect_to_wireless_network"
                    })
                  }
                  class="flex items-center justify-center gap-1 bg-secondary p-2 cursor-pointer rounded-md"
                >
                  <div class="truncate text-xs text-gray-1">connect</div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
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
      <div class={"flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Service Logs
        </h1>

        <div :if={@count > 0}>
          <%= for log <- @logs do %>
            <div class="flex flex-col p-3 mb-2 bg-primary rounded-lg font-light">
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
      <div class={"flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Device Logs
        </h1>

        <div :if={!(@count == 0)}>
          <%= for log <- @logs do %>
            <div class="flex flex-col p-3 mb-2 bg-primary rounded-lg font-light">
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
      <%= sidebar_header(assigns, %{
        header: "Blocklist",
        body: "List of manually blocked domains for connected systems and devices"
      }) %>

      <div class="flex flex-row gap-1 justify-end my-2">
        <%!-- Actions to take --%>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Domain to block for the entire system"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Sentinel.Schema.Blacklist.data(:system),
              "default_values" => %{},
              "action" => "add_system_domain_block"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md"
        >
          <.icon class="w-4 h-4" name="hero-no-symbol" />
          <div class="truncate text-xs text-gray-1">System Block</div>
        </div>

        <div
          phx-click="modal_open"
          phx-value-modal_title="Domain to block for a user"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Sentinel.Schema.Blacklist.data(:user),
              "default_values" => %{},
              "action" => "add_user_domain_block"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md"
        >
          <.icon class="w-4 h-4" name="hero-no-symbol" />
          <div class="truncate text-xs text-gray-1">Device Block</div>
        </div>
      </div>

      <div class={"flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Domains Blocked
        </h1>

        <div :if={@count > 0}>
          <%= for %{"domain" => domain, "ip" => ip, "mac" => mac, "ttl" => ttl, "type" => type} <- @blacklist do %>
            <div class="flex flex-col p-3 mb-2 bg-primary rounded-lg font-light">
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
                  phx-click="modal_open"
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
                        "type" => "remove_blocked_domain",
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
      <div class={"flex flex-col #{if @count == 0, do: "items-center justify-center", else: ""}"}>
        <h1 :if={@count == 0} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Logs Archived
        </h1>

        <div :if={@count > 0}>
          <%= for log_file <- @files do %>
            <div class="flex flex-col p-3 mb-2 bg-primary rounded-lg font-light">
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
                  :if={log_file !== "_data.log"}
                  phx-click="modal_open"
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
                      "payload" => %{"type" => "backup_file_delete", "data" => %{"file" => log_file}}
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
  defp sidebar_header(assigns, %{header: header, body: body}) do
    assigns =
      assigns
      |> assign(header: header)
      |> assign(body: body)

    ~H"""
    <div class="min-h-[170px] bg-primary bg-gradient-to-r from-secondary to-primary rounded-md p-3">
      <div class="text-xl font-medium"><%= @header %></div>
      <div class="text-sm">
        <%= @body %>
      </div>
    </div>
    """
  end
end

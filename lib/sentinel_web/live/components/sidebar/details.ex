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
    <div class="flex flex-col items-center justify-center p-5 h-full">
      <.icon class="w-[50px] h-[50px] text-green" name="hero-shield-check" />
      <h1 class="text-2xl font-light text-gray-2 my-4 text-center">System is running as expected.</h1>
    </div>
    """
  end

  @spec render(%{:view => :node, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :node} = assigns) do
    data = Map.get(assigns, :data)

    assigns =
      assigns
      |> assign(has_data: !Enum.empty?(data))

    ~H"""
    <div class="bg-secondary p-2 h-full">
      <div :if={@has_data}>
        <%!-- Sidebar header that will house metadat?  --%>
        <%= sidebar_header(assigns, %{
          header: data.name,
          body:
            "A reference to a running service accessible from this device over the network. This tracks availability and allows exposure to the internet"
        }) %>
      </div>

      <div :if={@has_data} class="flex flex-row gap-1 justify-end my-2">
        <%!-- Actions to take --%>

        <%!-- Actions Connect/Disconnect Tunnel --%>
        <div
          :if={Enum.empty?(data.tunnel)}
          phx-click="modal_open"
          phx-value-modal_title="Connect to Cloudflare Tunnel"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Sentinel.Schema.Cloudflare.data(:add),
              "default_values" => %{
                service: "#{data.ip}:#{data.port}"
              },
              "action" => "connect_cloudflare"
            })
          }
          class="flex items-center justify-center gap-1 bg-purple p-2 cursor-pointer rounded-md"
        >
          <.icon name="hero-globe-alt" class="h-5 w-5" />
          <div class="truncate text-xs">Connect Tunnel</div>
        </div>

        <div
          :if={!Enum.empty?(data.tunnel)}
          phx-click="modal_open"
          phx-value-modal_title="Disconnect Cloudflare Tunnel?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" => "Are you sure you want make node inaccessible over the internet?"
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Remove Tunnel",
              "payload" => %{
                "type" => "disconnect_cloudflare",
                "data" => %{"subdomain" => data.tunnel["subdomain"]}
              }
            })
          }
          class="flex items-center justify-center gap-1 bg-purple p-2 cursor-pointer rounded-md"
        >
          <.icon name="hero-globe-alt" class="h-5 w-5" />
          <div class="truncate text-xs">Disconnect Tunnel</div>
        </div>

        <%!-- Actions Remove Node --%>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Remove Node?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" => "Are you sure you want to remove the node? (note if there is a tunnel, this will be disconnected as well)"
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Remove",
              "payload" => %{
                "type" => "remove_instance",
                "data" => %{"id" => data.id, "subdomain" => data.tunnel["subdomain"]}
              }
            })
          }
          class="flex items-center justify-center gap-1 bg-red p-2 cursor-pointer rounded-md"
        >
          <.icon name="hero-no-symbol" class="h-5 w-5" />
          <div class="truncate text-xs">Remove Node</div>
        </div>
      </div>

      <div class={"flex flex-col #{if !@has_data, do: "items-center justify-center p-3 h-full", else: ""}"}>
        <h1 :if={!@has_data} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Node details
        </h1>

        <div :if={@has_data}>
          <div class="flex flex-col p-3 mb-2 bg-primary rounded-lg font-light">
            <div class="text-sm truncate">
              <span class="font-bold">Name:</span> <%= data.name %>
            </div>
            <div class="text-sm truncate">
              <span class="font-bold">IP:</span> <%= data.ip %>
            </div>
            <div class="text-sm truncate">
              <span class="font-bold">Port:</span> <%= data.port %>
            </div>
          </div>
        </div>
      </div>
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
    ~H"""
    <div class="bg-secondary p-2 h-full">
      <div class="flex flex-col items-center justify-center">
        <h1 class="text-2xl font-light text-gray-2 my-4 text-center">
          No device Information
        </h1>

        <%!-- TODO: Adding custom device detail settings here --%>
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
    <div class="bg-primary bg-gradient-to-r from-secondary to-primary rounded-md p-3">
      <div class="text-xl font-medium"><%= @header %></div>
      <div class="text-sm">
        <%= @body %>
      </div>
    </div>
    """
  end
end

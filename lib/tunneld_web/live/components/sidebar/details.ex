defmodule TunneldWeb.Live.Components.Sidebar.Details do
  @moduledoc """
  The list of sidebar details to render
  """
  use TunneldWeb, :live_component

  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:details")
    end

    {:ok, socket}
  end

  def update(assigns, socket) do
    view = Map.get(assigns, :view, socket.assigns[:view] || :system_overview)
    web_authn = Map.get(assigns, :web_authn, socket.assigns[:web_authn] || false)
    data = Map.get(assigns, :data, %{})

    socket =
      socket
      |> assign(:view, view)
      |> assign(:data, data)
      |> assign(:web_authn, web_authn)

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

  @spec render(%{:view => :authentication, optional(any()) => any()}) ::
          Phoenix.LiveView.Rendered.t()
  def render(%{view: :authentication, web_authn: web_authn} = assigns) do
    assigns = assign(assigns, :web_authn, Map.get(assigns, web_authn, false))

    ~H"""
    <div class="bg-secondary p-2 h-full" id="auth" phx-hook="Auth">
      <%!-- Sidebar header that will house metadat?  --%>
      <%= sidebar_header(assigns, %{
        header: "Authentication",
        body:
          "Authentication options to access the application dashboard. WebAuthn (required) after you expose dashboard as an resource.
        This is needed in order to remotely access resources"
      }) %>

      <div class="flex flex-row gap-1 justify-end my-2">
        <%!-- Actions to take --%>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Reset Login?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" =>
                "This will reset your login details. New details will be prompted for and required on your next login"
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Reset",
              "payload" => %{
                "type" => "revoke_login_creds",
                "data" => %{}
              }
            })
          }
          class="flex grow items-center justify-center gap-1 bg-red p-2 cursor-pointer rounded-md w-1/2"
        >
          <.icon name="hero-no-symbol" class="h-5 w-5" />
          <div class="truncate text-xs">Reset Login</div>
        </div>

        <%!-- Not allowed if the scheme is not HTTPS and we dont have a domain --%>
        <div
          :if={!@web_authn}
          class="flex grow items-center justify-center gap-1 bg-gray-2 p-2 rounded-md w-1/2"
        >
          <.icon name="hero-finger-print" class="h-5 w-5" />
          <div class="truncate text-xs">WebAuthn (disabled)</div>
        </div>
        <%!-- We have the option to generate --%>
        <div
          :if={@web_authn}
          phx-click="trigger_action"
          phx-value-action="configure_web_authn"
          phx-value-data={Jason.encode!(%{})}
          class="flex grow items-center justify-center gap-1 bg-purple p-2 cursor-pointer rounded-md w-1/2"
        >
          <.icon name="hero-finger-print" class="h-5 w-5" />
          <div class="truncate text-xs">WebAuthn</div>
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :resource, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :resource} = assigns) do
    data = Map.get(assigns, :data)

    assigns =
      assigns
      |> assign(has_data: is_map(data) and map_size(data) > 0)
      |> assign(gateway: Application.get_env(:tunneld, :network)[:gateway])
      |> assign(data: data)

    ~H"""
    <div class="bg-secondary p-2 h-full">
      <div :if={@has_data}>
        <%= sidebar_header(assigns, %{
          header: @data.name,
          body:
            @data.description ||
              "A reference to a running service accessible from this device over the network. This tracks availability and allows exposure to the internet"
        }) %>
      </div>

      <div :if={@has_data} class="flex flex-row gap-1 justify-end my-2">
        <%!-- Actions: Remove Resource only --%>
        <div
          phx-click="modal_open"
          phx-value-modal_title="Remove Resource?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" => "Are you sure you want to remove the resource?"
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Remove",
              "payload" => %{
                "type" => "remove_share",
                "data" => %{"id" => @data.id, "kind" => @data.kind}
              }
            })
          }
          class="flex items-center justify-center gap-1 bg-red p-2 cursor-pointer rounded-md"
        >
          <.icon name="hero-no-symbol" class="h-5 w-5" />
          <div class="truncate text-xs">Remove Resource</div>
        </div>
      </div>

      <div class={"flex flex-col #{if !@has_data, do: "items-center justify-center p-3 h-full", else: ""}"}>
        <h1 :if={!@has_data} class="text-2xl font-light text-gray-2 my-4 text-center">
          No Resource details
        </h1>

        <div :if={@has_data}>
          <div class="flex flex-col p-3 mb-2 bg-primary rounded-lg font-light">
            <div class="text-sm truncate">
              <span class="font-bold">Name:</span> <%= @data.name %>
            </div>
            <div class="text-sm truncate">
              <span class="font-bold">IP:</span> <%= @data.ip %>
            </div>
            <div class="text-sm truncate">
              <span class="font-bold">Port:</span> <%= @data.port %>
            </div>
          </div>

          <% tunneld = @data.tunneld || %{} %>
          <div :if={!Enum.empty?(tunneld)} class="mt-3">
            <div class="py-2">
              <h2 class="text-sm font-semibold">Resources</h2>
            </div>

            <div class="grid grid-cols-1 gap-2">
              <% available_kinds =
                ~w(public private access)
                |> Enum.filter(fn k -> not is_nil(get_in(tunneld, ["units", k])) end) %>

              <%= for kind <- available_kinds do %>
                <% reserved =
                  case kind do
                    "access" -> get_in(tunneld, ["reserved", "private"])
                    _ -> get_in(tunneld, ["reserved", kind])
                  end %>
                <% enabled? = get_in(tunneld, ["enabled", kind]) == true %>
                <% unit = get_in(tunneld, ["units", kind, "unit"]) %>
                <% unit_id = get_in(tunneld, ["units", kind, "id"]) %>

                <div class="bg-primary rounded-lg p-3">
                  <div class="flex items-center justify-between">
                    <div class="text-sm font-medium capitalize"><%= kind %> instance</div>
                    <label
                      phx-click="toggle_share_access"
                      phx-value-payload={
                        Jason.encode!(%{"id" => unit_id, "enable" => !enabled?, "kind" => @data.kind})
                      }
                      class="relative inline-flex items-center cursor-pointer"
                    >
                      <input type="checkbox" class="sr-only peer" checked={enabled?} />
                      <div class="w-9 h-5 bg-light_purple rounded-full peer-checked:bg-purple relative after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-light_purple after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-4">
                      </div>
                    </label>
                  </div>

                  <div class="mt-2 grid grid-rows-1 md:grid-rows-3 gap-2 text-xs">
                    <div class="truncate">
                      <span class="font-semibold">Reserved:</span>
                      <span class="ml-1"><%= reserved || "—" %></span>
                    </div>
                    <div class="truncate">
                      <span class="font-semibold">Systemd Unit:</span>
                      <span class="ml-1"><%= unit || "—" %></span>
                    </div>
                    <div class="truncate">
                      <span class="font-semibold">Unit ID:</span>
                      <span class="ml-1"><%= unit_id || "—" %></span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :zrok, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :zrok} = assigns) do
    data = Map.get(assigns, :data, %{})

    # unset check
    unset_check = Map.get(data, :api_endpoint, "") |> String.contains?("unset")
    default_endpoint = if unset_check, do: nil, else: Map.get(data, :api_endpoint, nil)

    assigns =
      assigns
      |> assign(enabled: Map.get(data, :enabled?, nil))
      |> assign(endpoint: default_endpoint)
      |> assign(is_unset: unset_check)
      |> assign(has_data: not Enum.empty?(data))

    ~H"""
    <div class="bg-secondary p-2 h-full">
      <%!-- Sidebar header that will house metadat?  --%>
      <%= sidebar_header(assigns, %{
        header: "Overlay Network Settings",
        body: "Set up this device to operate within your overlay control plane environment"
      }) %>

      <div :if={@has_data} class="flex flex-row gap-1 justify-end my-2">
        <%!-- Setup endpoint  --%>
        <div
          :if={not @is_unset}
          phx-click="modal_open"
          phx-value-modal_title="Disconnect from Control Plane?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" =>
                "This will disconnect the gateway from the current network. All resources and private access will stop working. You will need to enable them once you connect to a network again."
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Disconnect Control Plane",
              "payload" => %{
                "type" => "configure_disable_control_plane",
                "data" => %{}
              }
            })
          }
          class="flex items-center justify-center gap-1 bg-red p-2 cursor-pointer rounded-md"
        >
          <.icon name="hero-no-symbol" class="h-5 w-5" />
          <div class="truncate text-xs">Disconnect Control Plane</div>
        </div>

        <div
          :if={@is_unset}
          phx-click="modal_open"
          phx-value-modal_title="Configure Network Endpoint"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Tunneld.Schema.Zrok.data(:endpoint),
              "default_values" => %{
                url: @endpoint
              },
              "action" => "configure_enable_control_plane"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md"
        >
          <.icon class="w-4 h-4" name="hero-globe-alt" />
          <div class="truncate text-xs text-gray-1">Configure Control Plane</div>
        </div>

        <%!-- enabled options --%>
        <div
          :if={@enabled}
          phx-click="modal_open"
          phx-value-modal_title="Disable and disconnect device?"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "string",
              "data" =>
                "This will disable your device and disconnect it from the current account as an environment"
            })
          }
          phx-value-modal_actions={
            Jason.encode!(%{
              "title" => "Disable Environment",
              "payload" => %{
                "type" => "configure_disable_environment",
                "data" => %{}
              }
            })
          }
          class="flex items-center justify-center gap-1 bg-red p-2 cursor-pointer rounded-md"
        >
          <.icon name="hero-no-symbol" class="h-5 w-5" />
          <div class="truncate text-xs">Disable Device</div>
        </div>

        <div
          :if={not @is_unset and not @enabled}
          phx-click="modal_open"
          phx-value-modal_title="Configure device"
          phx-value-modal_body={
            Jason.encode!(%{
              "type" => "schema",
              "data" => Tunneld.Schema.Zrok.data(:conf_device),
              "default_values" => %{},
              "action" => "configure_enable_environment"
            })
          }
          class="flex items-center justify-center gap-1 bg-primary p-2 cursor-pointer rounded-md"
        >
          <.icon class="w-4 h-4" name="hero-link" />
          <div class="truncate text-xs text-gray-1">Enable Device</div>
        </div>
      </div>
    </div>
    """
  end

  @spec render(%{:view => :blocklist, optional(any()) => any()}) :: Phoenix.LiveView.Rendered.t()
  def render(%{view: :blocklist} = assigns) do
    data = Map.get(assigns, :data)

    ~H"""
    <div class="bg-secondary p-2 h-full">
      <%!-- Sidebar header that will house blocklist metadata --%>
      <%= sidebar_header(assigns, %{
        header: "DNS Blocklist",
        body:
          "This shows the metadata for the DNS sinkhole currently in use on this device. You can review the details below or fetch the latest version."
      }) %>

      <pre
        class="bg-gray-900 text-gray-100 text-xs p-3 rounded-md overflow-auto"
      ><%= Jason.encode!(data, pretty: true) %></pre>

      <div class="flex flex-row gap-1 justify-end my-2">
        <%!-- Actions to take --%>
        <div
          phx-click="trigger_action"
          phx-value-action="update_blacklist"
          phx-value-data={Jason.encode!(%{})}
          class="flex items-center justify-center gap-1 bg-purple p-2 cursor-pointer rounded-md"
        >
          <.icon class="w-4 h-4" name="hero-arrow-path" />
          <div class="truncate text-xs">Update</div>
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
                      "data" => Tunneld.Schema.Wlan.data(%{title: ssid}),
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

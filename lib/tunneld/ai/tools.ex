defmodule Tunneld.Ai.Tools do
  @moduledoc """
  Defines the tool schemas that map LLM function calls to
  `Dashboard.Actions.perform/3` action names.

  Each tool is an OpenAI-compatible function calling schema. The model
  selects which tool to call based on user intent, and the result is
  routed through the existing action dispatch layer.
  """

  @action_map %{
    "wifi_scan" => "scan_for_wireless_networks",
    "wifi_connect" => "connect_to_wireless_network",
    "wifi_disconnect" => "disconnect_from_wireless_network",
    "resource_add" => "add_share",
    "resource_remove" => "remove_share",
    "resource_toggle" => "toggle_share_access",
    "service_restart" => "restart_service",
    "service_logs" => "refresh_service_logs",
    "zrok_enable" => "configure_enable_environment",
    "zrok_disable" => "configure_disable_environment",
    "blocklist_update" => "update_blocklist",
    "sqm_set" => "set_sqm",
    "device_revoke" => "revoke_release_ip"
  }

  @destructive_tools ~w(resource_remove device_revoke wifi_disconnect zrok_disable)

  @doc """
  Returns the mapping of tool names to `Dashboard.Actions` action names.
  """
  def action_map, do: @action_map

  @doc """
  Returns `true` if the tool requires explicit user confirmation before execution.
  """
  def destructive?(tool_name), do: tool_name in @destructive_tools

  @doc """
  Returns all tool definitions as OpenAI function calling schemas.
  """
  def definitions do
    [
      function_tool("wifi_scan", "Scan for available Wi-Fi networks nearby", %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      }),
      function_tool(
        "wifi_connect",
        "Connect to a Wi-Fi network with the given SSID and password",
        %{
          "type" => "object",
          "properties" => %{
            "ssid" => %{"type" => "string", "description" => "The Wi-Fi network name"},
            "password" => %{"type" => "string", "description" => "The Wi-Fi password"}
          },
          "required" => ["ssid", "password"]
        }
      ),
      function_tool("wifi_disconnect", "Disconnect from the current Wi-Fi network", %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      }),
      function_tool("resource_add", "Create a new shared resource (zrok share with nginx proxy)", %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "Name for the share"},
          "pool" => %{
            "type" => "string",
            "description" => "Comma-separated backend addresses (e.g. 192.168.1.10:8080)"
          },
          "description" => %{
            "type" => "string",
            "description" => "Optional description of the share"
          }
        },
        "required" => ["name", "pool"]
      }),
      function_tool("resource_remove", "Remove an existing shared resource", %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string", "description" => "The resource ID to remove"},
          "kind" => %{
            "type" => "string",
            "enum" => ["host", "access"],
            "description" => "Type of resource"
          }
        },
        "required" => ["id", "kind"]
      }),
      function_tool("resource_toggle", "Enable or disable a shared resource", %{
        "type" => "object",
        "properties" => %{
          "payload" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string", "description" => "The resource ID"},
              "enable" => %{"type" => "boolean", "description" => "Enable or disable"},
              "kind" => %{
                "type" => "string",
                "enum" => ["host", "access"],
                "description" => "Type of resource"
              }
            },
            "required" => ["id", "enable", "kind"]
          }
        },
        "required" => ["payload"]
      }),
      function_tool("service_restart", "Restart a system service", %{
        "type" => "object",
        "properties" => %{
          "id" => %{
            "type" => "string",
            "enum" => ["dnsmasq", "dhcpcd", "dnscrypt-proxy", "nginx"],
            "description" => "The service to restart"
          }
        },
        "required" => ["id"]
      }),
      function_tool("service_logs", "View recent logs for a system service", %{
        "type" => "object",
        "properties" => %{
          "id" => %{
            "type" => "string",
            "enum" => ["dnsmasq", "dhcpcd", "dnscrypt-proxy", "nginx"],
            "description" => "The service to view logs for"
          }
        },
        "required" => ["id"]
      }),
      function_tool("zrok_enable", "Enable the device on the zrok overlay network", %{
        "type" => "object",
        "properties" => %{
          "account_token" => %{
            "type" => "string",
            "description" => "The zrok account token"
          }
        },
        "required" => ["account_token"]
      }),
      function_tool("zrok_disable", "Disable the device from the zrok overlay network", %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      }),
      function_tool("blocklist_update", "Update the DNS blocklist from remote sources", %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      }),
      function_tool(
        "sqm_set",
        "Configure Smart Queue Management (SQM) for bufferbloat reduction",
        %{
          "type" => "object",
          "properties" => %{
            "download" => %{
              "type" => "integer",
              "description" => "Download speed limit in mbit"
            },
            "upload" => %{"type" => "integer", "description" => "Upload speed limit in mbit"},
            "enabled" => %{"type" => "boolean", "description" => "Enable or disable SQM"}
          },
          "required" => ["enabled"]
        }
      ),
      function_tool("device_revoke", "Revoke a device's DHCP lease by MAC address", %{
        "type" => "object",
        "properties" => %{
          "mac" => %{
            "type" => "string",
            "description" => "The MAC address of the device to revoke"
          }
        },
        "required" => ["mac"]
      })
    ]
  end

  defp function_tool(name, description, parameters) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => description,
        "parameters" => parameters
      }
    }
  end
end

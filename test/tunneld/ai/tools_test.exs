defmodule Tunneld.Ai.ToolsTest do
  use ExUnit.Case, async: true

  alias Tunneld.Ai.Tools

  describe "definitions/0" do
    test "returns a non-empty list of tool schemas" do
      defs = Tools.definitions()
      assert is_list(defs)
      assert length(defs) > 0
    end

    test "every definition has the expected structure" do
      for tool <- Tools.definitions() do
        assert tool["type"] == "function"
        assert is_binary(tool["function"]["name"])
        assert is_binary(tool["function"]["description"])
        assert is_map(tool["function"]["parameters"])
      end
    end

    test "every tool name has a corresponding action mapping" do
      action_map = Tools.action_map()

      for tool <- Tools.definitions() do
        name = tool["function"]["name"]
        assert Map.has_key?(action_map, name), "Tool #{name} missing from action_map"
      end
    end
  end

  describe "action_map/0" do
    test "maps to known Dashboard.Actions action names" do
      known_actions =
        ~w(scan_for_wireless_networks connect_to_wireless_network disconnect_from_wireless_network
           add_share remove_share toggle_share_access restart_service refresh_service_logs
           configure_enable_environment configure_disable_environment update_blocklist
           set_sqm revoke_release_ip)

      for {_tool, action} <- Tools.action_map() do
        assert action in known_actions, "Action #{action} is not a known Dashboard action"
      end
    end
  end

  describe "destructive?/1" do
    test "returns true for destructive tools" do
      assert Tools.destructive?("resource_remove")
      assert Tools.destructive?("device_revoke")
      assert Tools.destructive?("wifi_disconnect")
      assert Tools.destructive?("zrok_disable")
    end

    test "returns false for non-destructive tools" do
      refute Tools.destructive?("wifi_scan")
      refute Tools.destructive?("wifi_connect")
      refute Tools.destructive?("service_logs")
      refute Tools.destructive?("blocklist_update")
    end
  end
end

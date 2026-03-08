defmodule Tunneld.Ai.ExecutorTest do
  use ExUnit.Case, async: true

  alias Tunneld.Ai.Executor

  describe "build_artifact/1" do
    test "builds correct artifact structure from tool call" do
      tool_call = %{
        "id" => "call_123",
        "type" => "function",
        "function" => %{
          "name" => "wifi_scan",
          "arguments" => "{}"
        }
      }

      artifact = Executor.build_artifact(tool_call)
      assert artifact.type == :tool_call
      assert artifact.tool_name == "wifi_scan"
      assert artifact.tool_call_id == "call_123"
      assert artifact.arguments == %{}
      assert is_map(artifact.schema)
      assert is_binary(artifact.description)
    end

    test "marks destructive tools as requiring confirmation" do
      tool_call = %{
        "id" => "call_456",
        "type" => "function",
        "function" => %{
          "name" => "resource_remove",
          "arguments" => Jason.encode!(%{"id" => "abc", "kind" => "host"})
        }
      }

      artifact = Executor.build_artifact(tool_call)
      assert artifact.requires_confirmation == true
    end

    test "non-destructive tools do not require confirmation" do
      tool_call = %{
        "id" => "call_789",
        "type" => "function",
        "function" => %{
          "name" => "blocklist_update",
          "arguments" => "{}"
        }
      }

      artifact = Executor.build_artifact(tool_call)
      assert artifact.requires_confirmation == false
    end

    test "parses arguments JSON" do
      tool_call = %{
        "id" => "call_100",
        "type" => "function",
        "function" => %{
          "name" => "wifi_connect",
          "arguments" => Jason.encode!(%{"ssid" => "MyNetwork", "password" => "secret"})
        }
      }

      artifact = Executor.build_artifact(tool_call)
      assert artifact.arguments["ssid"] == "MyNetwork"
      assert artifact.arguments["password"] == "secret"
    end
  end

  describe "format_result/2" do
    test "formats success result as tool message" do
      result = Executor.format_result("call_123", {:ok, "done"})
      assert result["role"] == "tool"
      assert result["tool_call_id"] == "call_123"
      decoded = Jason.decode!(result["content"])
      assert decoded["status"] == "success"
    end

    test "formats error result as tool message" do
      result = Executor.format_result("call_123", {:error, "not found"})
      assert result["role"] == "tool"
      decoded = Jason.decode!(result["content"])
      assert decoded["status"] == "error"
    end

    test "formats raw values as success" do
      result = Executor.format_result("call_123", :ok)
      decoded = Jason.decode!(result["content"])
      assert decoded["status"] == "success"
    end
  end
end

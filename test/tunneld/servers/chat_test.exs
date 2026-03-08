defmodule Tunneld.Servers.ChatTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.{Ai, Chat}

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "tunneld_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    original_fs = Application.get_env(:tunneld, :fs)
    original_mock = Application.get_env(:tunneld, :mock_data)

    Application.put_env(:tunneld, :fs, root: tmp_dir, auth: "auth.json", ai: "ai.json")
    Application.put_env(:tunneld, :mock_data, true)

    Ai.save_config(%{
      "base_url" => "http://localhost:11434/v1",
      "api_key" => "",
      "model" => "llama3",
      "mock" => true
    })

    Chat.clear_history()

    on_exit(fn ->
      Application.put_env(:tunneld, :fs, original_fs)
      Application.put_env(:tunneld, :mock_data, original_mock)
      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  describe "send_message/1" do
    test "returns text response for general input" do
      assert {:ok, [_user, assistant], []} = Chat.send_message("hello")
      assert assistant["role"] == "assistant"
      assert is_binary(assistant["content"])
    end

    test "returns tool call artifact for wifi-related input" do
      assert {:ok, [_user, assistant], artifacts} = Chat.send_message("scan wifi")
      assert assistant["role"] == "assistant"
      assert length(artifacts) > 0
      [artifact | _] = artifacts
      assert artifact.type == :tool_call
      assert artifact.tool_name == "wifi_scan"
    end
  end

  describe "approve_tool_call/2" do
    test "executes tool and returns follow-up response" do
      {:ok, _messages, artifacts} = Chat.send_message("scan wifi")
      [artifact | _] = artifacts

      assert {:ok, [_tool_result, followup], _} =
               Chat.approve_tool_call(artifact.tool_call_id)

      assert followup["role"] == "assistant"
    end

    test "returns error for unknown tool call id" do
      assert {:error, :not_found} = Chat.approve_tool_call("nonexistent")
    end
  end

  describe "reject_tool_call/1" do
    test "returns acknowledgment response" do
      {:ok, _messages, artifacts} = Chat.send_message("scan wifi")
      [artifact | _] = artifacts

      assert {:ok, [_rejection, followup], _} =
               Chat.reject_tool_call(artifact.tool_call_id)

      assert followup["role"] == "assistant"
    end

    test "returns error for unknown tool call id" do
      assert {:error, :not_found} = Chat.reject_tool_call("nonexistent")
    end
  end

  describe "get_history/0" do
    test "returns empty list initially" do
      assert [] = Chat.get_history()
    end

    test "accumulates messages" do
      Chat.send_message("hello")
      history = Chat.get_history()
      assert length(history) >= 2
    end
  end

  describe "clear_history/0" do
    test "resets message history" do
      Chat.send_message("hello")
      assert length(Chat.get_history()) > 0

      Chat.clear_history()
      assert [] = Chat.get_history()
    end
  end
end

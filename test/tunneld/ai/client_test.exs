defmodule Tunneld.Ai.ClientTest do
  use ExUnit.Case, async: true

  alias Tunneld.Ai.Client

  setup do
    original_mock = Application.get_env(:tunneld, :mock_data)
    Application.put_env(:tunneld, :mock_data, true)

    on_exit(fn ->
      Application.put_env(:tunneld, :mock_data, original_mock)
    end)

    config = %{"base_url" => "http://localhost:11434/v1", "api_key" => "", "model" => "llama3"}
    %{config: config}
  end

  describe "list_models/1" do
    test "returns model list in mock mode", %{config: config} do
      assert {:ok, models} = Client.list_models(config)
      assert is_list(models)
      assert "llama3" in models
      assert "mistral" in models
    end
  end

  describe "chat_completion/3" do
    test "returns text response for general input", %{config: config} do
      messages = [%{"role" => "user", "content" => "hello"}]
      assert {:ok, message} = Client.chat_completion(config, messages)
      assert is_binary(message["content"])
      assert message["role"] == "assistant"
    end

    test "returns tool call for wifi-related input", %{config: config} do
      messages = [%{"role" => "user", "content" => "scan for wifi networks"}]
      assert {:ok, message} = Client.chat_completion(config, messages)
      assert is_list(message["tool_calls"])
      [tool_call | _] = message["tool_calls"]
      assert tool_call["function"]["name"] == "wifi_scan"
    end

    test "returns tool call for service-related input", %{config: config} do
      messages = [%{"role" => "user", "content" => "restart nginx"}]
      assert {:ok, message} = Client.chat_completion(config, messages)
      assert is_list(message["tool_calls"])
      [tool_call | _] = message["tool_calls"]
      assert tool_call["function"]["name"] == "service_restart"
    end
  end

  describe "headers/1" do
    test "includes Bearer token when API key is present" do
      config = %{"api_key" => "sk-test-key"}
      headers = Client.headers(config)
      assert {"Authorization", "Bearer sk-test-key"} in headers
      assert {"Content-Type", "application/json"} in headers
    end

    test "excludes Bearer token when API key is empty" do
      config = %{"api_key" => ""}
      headers = Client.headers(config)
      refute Enum.any?(headers, fn {k, _} -> k == "Authorization" end)
      assert {"Content-Type", "application/json"} in headers
    end

    test "excludes Bearer token when no API key" do
      headers = Client.headers(%{})
      refute Enum.any?(headers, fn {k, _} -> k == "Authorization" end)
    end
  end
end

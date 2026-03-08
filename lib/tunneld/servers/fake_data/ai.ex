defmodule Tunneld.Servers.FakeData.Ai do
  @moduledoc """
  Mock data for the AI assistant in development and test environments.
  """

  @doc """
  Returns a sample AI configuration.
  """
  def get_config do
    %{
      "base_url" => "http://localhost:11434/v1",
      "api_key" => "",
      "model" => "llama3"
    }
  end

  @doc """
  Returns a sample list of available models.
  """
  def get_models do
    [
      %{"id" => "llama3", "object" => "model"},
      %{"id" => "mistral", "object" => "model"},
      %{"id" => "codellama", "object" => "model"}
    ]
  end

  @doc """
  Returns a mock chat completion response. Matches on message content to
  return either a text response or a tool call for testing purposes.
  """
  def chat_completion(messages, _tools) do
    last_message = List.last(messages)
    role = get_in(last_message, ["role"]) || ""
    content = get_in(last_message, ["content"]) || ""

    # After a tool result, always respond with text to avoid infinite loops
    if role == "tool" do
      text_response("Done. The action has been completed successfully. Is there anything else you'd like me to help with?")
    else
      cond do
        String.contains?(String.downcase(content), "wifi") or
            String.contains?(String.downcase(content), "scan") ->
          tool_call_response("wifi_scan", %{})

        String.contains?(String.downcase(content), "restart") ->
          tool_call_response("service_restart", %{"id" => "nginx"})

        String.contains?(String.downcase(content), "blocklist") ->
          tool_call_response("blocklist_update", %{})

        true ->
          text_response("I can help you manage your gateway. You can ask me to scan for WiFi networks, manage shares, restart services, or update blocklists.")
      end
    end
  end

  defp text_response(content) do
    %{
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => content
          }
        }
      ]
    }
  end

  defp tool_call_response(name, arguments) do
    %{
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              %{
                "id" => "call_#{:rand.uniform(100_000)}",
                "type" => "function",
                "function" => %{
                  "name" => name,
                  "arguments" => Jason.encode!(arguments)
                }
              }
            ]
          }
        }
      ]
    }
  end
end

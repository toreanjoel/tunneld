defmodule Tunneld.Ai.Client do
  @moduledoc """
  HTTP client for OpenAI-compatible LLM APIs.

  Supports any provider that implements the OpenAI chat completions interface:
  Ollama, LM Studio, OpenRouter, OpenAI, and others. In mock mode, delegates
  to `Tunneld.Servers.FakeData.Ai` for development and testing.
  """

  @models_timeout 5_000
  @completion_timeout 60_000

  @doc """
  Fetch available models from the provider.
  Returns `{:ok, [model_id]}` or `{:error, reason}`.
  """
  def list_models(%{"base_url" => base_url} = config) do
    if mock?(config) do
      models = Tunneld.Servers.FakeData.Ai.get_models()
      {:ok, Enum.map(models, & &1["id"])}
    else
      url = String.trim_trailing(base_url, "/") <> "/models"

      case HTTPoison.get(url, headers(config), recv_timeout: @models_timeout) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"data" => data}} ->
              {:ok, Enum.map(data, & &1["id"])}

            {:ok, _} ->
              {:error, :unexpected_response}

            {:error, _} ->
              {:error, :invalid_json}
          end

        {:ok, %HTTPoison.Response{status_code: status}} ->
          {:error, {:http_error, status}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Send a chat completion request with tool definitions.
  Returns `{:ok, message_map}` or `{:error, reason}`.

  The returned message map has either `"content"` (text response) or
  `"tool_calls"` (list of tool call requests from the model).
  """
  def chat_completion(%{"base_url" => base_url} = config, messages, tools \\ []) do
    if mock?(config) do
      response = Tunneld.Servers.FakeData.Ai.chat_completion(messages, tools)
      parse_completion(response)
    else
      url = String.trim_trailing(base_url, "/") <> "/chat/completions"

      body =
        %{
          "model" => Map.get(config, "model", ""),
          "messages" => messages
        }
        |> maybe_add_tools(tools)
        |> Jason.encode!()

      case HTTPoison.post(url, body, headers(config), recv_timeout: @completion_timeout) do
        {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, data} -> parse_completion(data)
            {:error, _} -> {:error, :invalid_json}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          {:error, {:http_error, status, resp_body}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Build request headers. Includes the Bearer token only when an API key is set.
  """
  def headers(%{"api_key" => key}) when is_binary(key) and key != "" do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{key}"}
    ]
  end

  def headers(_config) do
    [{"Content-Type", "application/json"}]
  end

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    Map.merge(body, %{"tools" => tools, "tool_choice" => "auto"})
  end

  defp parse_completion(%{"choices" => [%{"message" => message} | _]}) do
    {:ok, message}
  end

  defp parse_completion(_), do: {:error, :unexpected_response}

  defp mock?(config) do
    case Map.get(config, "mock") do
      nil -> Application.get_env(:tunneld, :mock_data, false)
      val -> val
    end
  end
end

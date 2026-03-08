defmodule Tunneld.Schema.Ai do
  @moduledoc """
  JSON Schema definitions for the AI assistant configuration form.
  """

  @doc """
  Returns the JSON Schema for the AI setup form.
  Accepts an optional map with a `:models` key to populate the model selector.
  """
  @spec data(map()) :: map()
  def data(opts \\ %{}) do
    models = Map.get(opts, :models, [])

    model_schema =
      if models != [] do
        %{
          "type" => "string",
          "enum" => models,
          "description" => "Select the model to use"
        }
      else
        %{
          "type" => "string",
          "description" => "Model name (e.g. llama3, gpt-4o)"
        }
      end

    %{
      "title" => "AI Assistant",
      "description" =>
        "Configure an AI assistant to help manage your gateway. A local provider like Ollama is recommended for privacy.",
      "type" => "object",
      "properties" => %{
        "base_url" => %{
          "type" => "string",
          "format" => "uri",
          "minLength" => 1,
          "default" => "http://localhost:11434/v1",
          "description" => "Provider URL (recommended: local Ollama at http://localhost:11434/v1)"
        },
        "api_key" => %{
          "type" => "string",
          "format" => "password",
          "description" => "API key (optional for local providers like Ollama)"
        },
        "model" => model_schema
      },
      "required" => ["base_url", "model"],
      "ui:order" => ["base_url", "api_key", "model"]
    }
  end
end

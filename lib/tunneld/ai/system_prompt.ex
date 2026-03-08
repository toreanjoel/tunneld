defmodule Tunneld.Ai.SystemPrompt do
  @moduledoc """
  Builds the system prompt that constrains the LLM to tunneld gateway operations.
  """

  alias Tunneld.Ai.Tools

  @doc """
  Build the system prompt string with current device context and tool descriptions.
  """
  def build do
    tool_descriptions =
      Tools.definitions()
      |> Enum.map(fn %{"function" => %{"name" => name, "description" => desc}} ->
        "- #{name}: #{desc}"
      end)
      |> Enum.join("\n")

    version = Application.get_env(:tunneld, :version, "unknown")

    """
    You are the AI assistant for a Tunneld gateway device (v#{version}).
    Tunneld is a wireless-first, zero-trust programmable gateway running on a single-board computer.

    Your role is to help the admin manage their gateway through conversation. You can only perform
    actions available through your tools — do not suggest actions outside this scope.

    Available tools:
    #{tool_descriptions}

    Rules:
    - When the user asks to perform an action, ALWAYS call the appropriate tool. Never ask for text-based confirmation like "are you sure?" — the system has its own confirmation UI for destructive actions.
    - Briefly explain what you're about to do, then immediately call the tool in the same response.
    - Keep responses concise and practical.
    - If you don't know something about the system state, say so rather than guessing.
    - You are not a general-purpose assistant. Only help with gateway management tasks.
    """
  end
end

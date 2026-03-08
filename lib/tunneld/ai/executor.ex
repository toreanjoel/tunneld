defmodule Tunneld.Ai.Executor do
  @moduledoc """
  Bridges LLM tool calls to `Dashboard.Actions.perform/3`.

  Translates tool call responses from the model into action dispatches,
  builds user-facing artifacts for confirmation, and formats execution
  results back into the message format the model expects.
  """

  alias Tunneld.Ai.Tools
  alias TunneldWeb.Live.Dashboard.Actions

  @doc """
  Execute a tool call by dispatching through `Dashboard.Actions.perform/3`.
  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def execute(tool_name, arguments, parent \\ self()) do
    case Map.get(Tools.action_map(), tool_name) do
      nil ->
        {:error, "Unknown tool: #{tool_name}"}

      action_name ->
        try do
          result = Actions.perform(action_name, arguments, parent)
          {:ok, result}
        rescue
          e -> {:error, Exception.message(e)}
        catch
          :exit, reason -> {:error, "Action failed: #{inspect(reason)}"}
        end
    end
  end

  @doc """
  Build an artifact map from a tool call for display in the chat UI.
  Includes the tool parameters schema for rendering a confirmation form.
  """
  def build_artifact(tool_call) do
    %{"id" => id, "function" => %{"name" => name, "arguments" => args_json}} = tool_call

    arguments =
      case Jason.decode(args_json) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    tool_def = Enum.find(Tools.definitions(), fn t -> t["function"]["name"] == name end)

    %{
      type: :tool_call,
      tool_name: name,
      tool_call_id: id,
      arguments: arguments,
      requires_confirmation: Tools.destructive?(name),
      schema: get_in(tool_def, ["function", "parameters"]),
      description: get_in(tool_def, ["function", "description"])
    }
  end

  @doc """
  Format an execution result as a tool response message for the next LLM turn.
  """
  def format_result(tool_call_id, result) do
    content =
      case result do
        {:ok, data} -> Jason.encode!(%{"status" => "success", "data" => inspect(data)})
        {:error, reason} -> Jason.encode!(%{"status" => "error", "reason" => inspect(reason)})
        other -> Jason.encode!(%{"status" => "success", "data" => inspect(other)})
      end

    %{
      "role" => "tool",
      "tool_call_id" => tool_call_id,
      "content" => content
    }
  end
end

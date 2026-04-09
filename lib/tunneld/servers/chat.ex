defmodule Tunneld.Servers.Chat do
  @moduledoc """
  Manages the AI chat session state and orchestrates the multi-turn
  tool-use conversation loop.

  Holds the message history in memory (not persisted to disk). Messages
  are automatically cleaned up after 24 hours. Since this is a single-admin
  device, only one chat session exists at a time.
  """
  use GenServer
  require Logger

  alias Tunneld.Ai.{Client, Executor, SystemPrompt, Tools}
  alias Tunneld.Servers.Ai

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  @cleanup_interval 86_400_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_cleanup()
    {:ok, initial_state()}
  end

  @doc """
  Send a user message and get the assistant's response.
  Returns `{:ok, new_messages}` where new_messages is the list of messages
  added to the conversation (assistant text or tool call artifacts).
  """
  def send_message(content) do
    GenServer.call(__MODULE__, {:send_message, content}, 90_000)
  end

  @doc """
  Approve a pending tool call and execute it. The result is fed back
  to the LLM for a follow-up response.
  Returns `{:ok, new_messages}` with the execution result and any follow-up.
  """
  def approve_tool_call(tool_call_id, arguments \\ nil) do
    GenServer.call(__MODULE__, {:approve_tool_call, tool_call_id, arguments}, 90_000)
  end

  @doc """
  Reject a pending tool call. Informs the LLM that the user declined.
  Returns `{:ok, new_messages}`.
  """
  def reject_tool_call(tool_call_id) do
    GenServer.call(__MODULE__, {:reject_tool_call, tool_call_id}, 90_000)
  end

  @doc """
  Returns the full message history for the current session.
  """
  def get_history do
    GenServer.call(__MODULE__, :get_history)
  end

  @doc """
  Clear all messages and pending tool calls, starting a fresh session.
  """
  def clear_history do
    GenServer.call(__MODULE__, :clear_history)
  end

  # Callbacks

  @impl true
  def handle_call({:send_message, content}, _from, state) do
    user_message = %{"role" => "user", "content" => content}
    messages = state.messages ++ [user_message]

    case get_completion(messages) do
      {:ok, assistant_message, artifacts} ->
        updated_messages = messages ++ [assistant_message]

        pending =
          Enum.reduce(artifacts, state.pending_tool_calls, fn artifact, acc ->
            Map.put(acc, artifact.tool_call_id, artifact)
          end)

        new_state = %{
          state
          | messages: updated_messages,
            pending_tool_calls: pending,
            last_activity: DateTime.utc_now()
        }

        broadcast_update(new_state)
        {:reply, {:ok, [user_message, assistant_message], artifacts}, new_state}

      {:error, reason} ->
        error_message = %{
          "role" => "assistant",
          "content" => "I encountered an error: #{inspect(reason)}. Please try again."
        }

        new_state = %{
          state
          | messages: messages ++ [error_message],
            last_activity: DateTime.utc_now()
        }

        broadcast_update(new_state)
        {:reply, {:ok, [user_message, error_message], []}, new_state}
    end
  end

  @impl true
  def handle_call({:approve_tool_call, tool_call_id, override_args}, _from, state) do
    case Map.pop(state.pending_tool_calls, tool_call_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {artifact, remaining_pending} ->
        arguments = override_args || artifact.arguments
        result = Executor.execute(artifact.tool_name, arguments)
        tool_result = Executor.format_result(tool_call_id, result)

        messages = state.messages ++ [tool_result]

        case get_completion(messages) do
          {:ok, followup_message, new_artifacts} ->
            updated_messages = messages ++ [followup_message]

            pending =
              Enum.reduce(new_artifacts, remaining_pending, fn a, acc ->
                Map.put(acc, a.tool_call_id, a)
              end)

            new_state = %{
              state
              | messages: updated_messages,
                pending_tool_calls: pending,
                last_activity: DateTime.utc_now()
            }

            broadcast_update(new_state)
            {:reply, {:ok, [tool_result, followup_message], new_artifacts}, new_state}

          {:error, reason} ->
            error_message = %{
              "role" => "assistant",
              "content" => "Action completed but I had trouble processing the result: #{inspect(reason)}"
            }

            new_state = %{
              state
              | messages: messages ++ [error_message],
                pending_tool_calls: remaining_pending,
                last_activity: DateTime.utc_now()
            }

            broadcast_update(new_state)
            {:reply, {:ok, [tool_result, error_message], []}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:reject_tool_call, tool_call_id}, _from, state) do
    case Map.pop(state.pending_tool_calls, tool_call_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {_artifact, remaining_pending} ->
        rejection = Executor.format_result(tool_call_id, {:error, "User rejected this action"})
        messages = state.messages ++ [rejection]

        case get_completion(messages) do
          {:ok, followup_message, new_artifacts} ->
            updated_messages = messages ++ [followup_message]

            pending =
              Enum.reduce(new_artifacts, remaining_pending, fn a, acc ->
                Map.put(acc, a.tool_call_id, a)
              end)

            new_state = %{
              state
              | messages: updated_messages,
                pending_tool_calls: pending,
                last_activity: DateTime.utc_now()
            }

            broadcast_update(new_state)
            {:reply, {:ok, [rejection, followup_message], new_artifacts}, new_state}

          {:error, _reason} ->
            ack = %{
              "role" => "assistant",
              "content" => "Understood, I won't perform that action."
            }

            new_state = %{
              state
              | messages: messages ++ [ack],
                pending_tool_calls: remaining_pending,
                last_activity: DateTime.utc_now()
            }

            broadcast_update(new_state)
            {:reply, {:ok, [rejection, ack], []}, new_state}
        end
    end
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, state.messages, state}
  end

  @impl true
  def handle_call(:clear_history, _from, _state) do
    new_state = initial_state()
    broadcast_update(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()

    new_state =
      case state.last_activity do
        nil ->
          state

        last when not is_nil(last) ->
          diff = DateTime.diff(now, last, :millisecond)

          if diff >= @cleanup_interval do
            initial_state()
          else
            state
          end
      end

    schedule_cleanup()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp get_completion(messages) do
    mock? = mock?()

    case get_ai_config(mock?) do
      {:ok, config} ->
        system_message = %{"role" => "system", "content" => SystemPrompt.build()}
        full_messages = [system_message | messages]

        case Client.chat_completion(config, full_messages, Tools.definitions()) do
          {:ok, %{"tool_calls" => tool_calls} = message} when is_list(tool_calls) ->
            artifacts = Enum.map(tool_calls, &Executor.build_artifact/1)
            {:ok, message, artifacts}

          {:ok, message} ->
            {:ok, message, []}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_ai_config(true = _mock?) do
    case Ai.read_config() do
      {:ok, config} -> {:ok, Map.put(config, "mock", true)}
      {:error, _} -> {:ok, Map.put(Tunneld.Servers.FakeData.Ai.get_config(), "mock", true)}
    end
  end

  defp get_ai_config(false) do
    case Ai.read_config() do
      {:ok, config} -> {:ok, Map.put_new(config, "mock", false)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_update(state) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:chat", %{
      id: "chat",
      data: %{
        messages: state.messages,
        pending_tool_calls: state.pending_tool_calls
      }
    })
  end

  defp schedule_cleanup do
    :timer.send_after(@cleanup_interval, :cleanup)
  end

  defp initial_state do
    %{
      messages: [],
      pending_tool_calls: %{},
      last_activity: nil
    }
  end
end

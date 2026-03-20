defmodule TunneldWeb.Live.Components.Chat do
  @moduledoc """
  Chat interface component for the AI assistant.

  Renders the full-screen chat view with message history, tool call
  artifacts with approve/reject actions, a thinking indicator, and
  model selection. Communicates with the Chat GenServer for all
  LLM interactions.
  """
  use TunneldWeb, :live_component

  alias Tunneld.Servers.{Ai, Chat}
  alias Tunneld.Ai.Client

  def mount(socket) do
    socket =
      socket
      |> assign(:messages, [])
      |> assign(:artifacts, %{})
      |> assign(:input, "")
      |> assign(:thinking, false)
      |> assign(:models, [])
      |> assign(:config, %{})
      |> assign(:typewriter_id, nil)

    {:ok, socket}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:parent_pid, Map.get(assigns, :parent_pid, socket.assigns[:parent_pid]))

    socket =
      case assigns do
        %{chat_update: %{messages: messages, artifacts: artifacts}} ->
          typewriter_id = find_last_assistant_idx(messages)

          socket
          |> assign(:messages, messages)
          |> assign(:artifacts, artifacts)
          |> assign(:thinking, false)
          |> assign(:typewriter_id, typewriter_id)

        _ ->
          unless socket.assigns[:config_loaded] do
            config = load_config()
            models = load_models(config)
            history = Chat.get_history()

            socket
            |> assign(:config, config)
            |> assign(:models, models)
            |> assign(:messages, history)
            |> assign(:config_loaded, true)
          else
            socket
          end
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full min-h-0" id={@id}>
      <div class="flex-shrink-0 flex items-center justify-between p-4 border-b border-secondary">
        <div class="flex items-center gap-3">
          <h1 class="text-lg font-medium">AI Assistant</h1>
          <form
            :if={length(@models) > 1}
            phx-change="select_model"
            phx-target={@myself}
          >
            <select
              name="model"
              class="bg-primary border border-secondary rounded-md text-xs px-2 py-1 text-gray-1"
            >
              <%= for model <- @models do %>
                <option value={model} selected={model == @config["model"]}><%= model %></option>
              <% end %>
            </select>
          </form>
        </div>

        <div class="flex items-center gap-2">
          <button
            phx-click="show_details"
            phx-value-type="ai_settings"
            phx-value-id="_"
            class="flex items-center justify-center bg-secondary p-1.5 rounded-md text-gray-1 hover:opacity-80"
          >
            <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
          </button>
          <button
            phx-click="clear_chat"
            phx-target={@myself}
            class="flex items-center gap-1 bg-secondary px-3 py-1.5 rounded-md text-xs text-gray-1 hover:opacity-80"
          >
            <.icon name="hero-plus" class="w-3 h-3" />
            New Chat
          </button>
          <button
            phx-click="close_details"
            class="flex items-center justify-center p-1.5 text-gray-1 hover:opacity-80"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
      </div>

      <div
        class="flex-1 min-h-0 overflow-y-auto p-4 space-y-4 system-scroll"
        id="chat-messages"
        phx-hook="ChatScroll"
      >
        <div
          :if={Enum.empty?(@messages)}
          class="flex flex-col items-center justify-center h-full text-gray-2"
        >
          <.icon name="hero-chat-bubble-left-right" class="w-12 h-12 mb-4 opacity-30" />
          <p class="text-sm">Ask me to help manage your gateway</p>
          <p class="text-xs mt-1 opacity-60">WiFi, shares, services, blocklists, and more</p>
        </div>

        <%= for {message, idx} <- Enum.with_index(@messages) do %>
          <%= render_message(assigns, message, idx) %>
        <% end %>

        <div :if={@thinking} class="flex items-start gap-3">
          <div class="bg-secondary rounded-lg p-3 max-w-[80%]">
            <div class="flex items-center gap-2 text-gray-1 text-sm">
              <svg class="animate-spin h-4 w-4" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none" />
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
              Thinking...
            </div>
          </div>
        </div>
      </div>

      <div :if={map_size(@artifacts) > 0} class="flex-shrink-0 px-4 pb-2 space-y-2">
        <%= for {_id, artifact} <- @artifacts do %>
          <div class="bg-secondary rounded-lg p-3 border border-purple border-opacity-30">
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center gap-2">
                <.icon name="hero-wrench-screwdriver" class="w-4 h-4 text-purple" />
                <span class="text-sm font-medium"><%= humanize_tool(artifact.tool_name) %></span>
              </div>
              <span
                :if={artifact.requires_confirmation}
                class="text-xs bg-red bg-opacity-20 text-red px-2 py-0.5 rounded"
              >
                Requires confirmation
              </span>
            </div>

            <p :if={artifact.description} class="text-xs text-gray-1 mb-2"><%= artifact.description %></p>

            <div :if={map_size(artifact.arguments) > 0} class="bg-primary rounded-md p-2 mb-2">
              <%= for {key, val} <- artifact.arguments do %>
                <div class="text-xs">
                  <span class="font-semibold text-gray-1"><%= key %>:</span>
                  <span class="ml-1"><%= inspect(val) %></span>
                </div>
              <% end %>
            </div>

            <div class="flex gap-2 justify-end">
              <button
                phx-click="reject_tool"
                phx-target={@myself}
                phx-value-tool_call_id={artifact.tool_call_id}
                disabled={@thinking}
                class="px-3 py-1 text-xs rounded-md bg-primary text-gray-1 hover:opacity-80 disabled:opacity-50"
              >
                Reject
              </button>
              <button
                phx-click="approve_tool"
                phx-target={@myself}
                phx-value-tool_call_id={artifact.tool_call_id}
                disabled={@thinking}
                class="px-3 py-1 text-xs rounded-md bg-green text-white hover:opacity-80 disabled:opacity-50"
              >
                Approve
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <div class="flex-shrink-0 p-4 border-t border-secondary">
        <form
          phx-submit="send_message"
          phx-target={@myself}
          id="chat-form"
        >
          <div class="flex gap-2 items-end">
            <textarea
              name="message"
              placeholder={if @thinking, do: "Waiting for response...", else: "Ask about your gateway..."}
              disabled={@thinking}
              autocomplete="off"
              rows="1"
              id="chat-input"
              phx-hook="ChatInput"
              class="flex-1 bg-secondary border-none rounded-lg px-4 py-2.5 text-sm text-white placeholder-gray-2 focus:ring-1 focus:ring-purple resize-none max-h-32 overflow-y-auto"
            ></textarea>
            <button
              type="submit"
              disabled={@thinking}
              class="bg-purple px-4 py-2.5 rounded-lg text-sm hover:opacity-80 disabled:opacity-50"
            >
              <.icon name="hero-paper-airplane" class="w-4 h-4" />
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp render_message(assigns, %{"role" => "user", "content" => content}, _idx) do
    assigns = assign(assigns, :content, content)

    ~H"""
    <div class="flex justify-end">
      <div class="bg-purple rounded-lg p-3 max-w-[80%]">
        <div class="text-sm whitespace-pre-wrap"><%= @content %></div>
      </div>
    </div>
    """
  end

  defp render_message(assigns, %{"role" => "assistant", "content" => content}, idx)
       when is_binary(content) do
    animate = assigns.typewriter_id == idx
    assigns = assigns |> assign(:html, md_to_html(content)) |> assign(:idx, idx) |> assign(:animate, animate)

    ~H"""
    <div class="flex items-start gap-3">
      <div class="bg-secondary rounded-lg p-3 max-w-[80%]">
        <div
          class="text-sm text-gray-1 chat-prose max-w-none"
          phx-hook="Typewriter"
          id={"msg-#{@idx}"}
          data-animate={to_string(@animate)}
        >
          <%= Phoenix.HTML.raw(@html) %>
        </div>
      </div>
    </div>
    """
  end

  defp render_message(assigns, %{"role" => "assistant", "tool_calls" => tool_calls}, _idx)
       when is_list(tool_calls) do
    names =
      Enum.map(tool_calls, fn tc ->
        humanize_tool(get_in(tc, ["function", "name"]) || "action")
      end)

    assigns = assign(assigns, :names, names)

    ~H"""
    <div class="flex items-start gap-3">
      <div class="bg-secondary rounded-lg p-3 max-w-[80%]">
        <p class="text-sm text-gray-1">
          I'd like to perform: <%= Enum.join(@names, ", ") %>
        </p>
      </div>
    </div>
    """
  end

  defp render_message(assigns, %{"role" => "tool", "content" => content}, _idx) do
    status = case Jason.decode(content || "{}") do
      {:ok, %{"status" => "success"}} -> :success
      {:ok, %{"status" => "error", "reason" => reason}} -> {:error, reason}
      _ -> :success
    end
    assigns = assign(assigns, :status, status)

    ~H"""
    <div class="flex items-start gap-3">
      <%= case @status do %>
        <% :success -> %>
          <div class="flex items-center gap-1.5 text-xs text-white py-1">
            <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5 text-purple" />
            <span>Done</span>
          </div>
        <% {:error, reason} -> %>
          <div class="flex items-center gap-1.5 text-xs text-white py-1">
            <.icon name="hero-x-circle-mini" class="w-3.5 h-3.5 text-red" />
            <span>Failed: <%= reason %></span>
          </div>
      <% end %>
    </div>
    """
  end

  defp render_message(assigns, %{"role" => "tool"}, _idx) do
    ~H"""
    <div class="flex items-start gap-3">
      <div class="flex items-center gap-1.5 text-xs text-white py-1">
        <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5 text-purple" />
        <span>Done</span>
      </div>
    </div>
    """
  end

  defp render_message(assigns, _message, _idx) do
    ~H"""
    """
  end

  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    parent = socket.assigns[:parent_pid]

    user_message = %{"role" => "user", "content" => String.trim(message)}
    messages = socket.assigns.messages ++ [user_message]

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:thinking, true)
      |> assign(:input, "")

    Task.start(fn ->
      result = Chat.send_message(String.trim(message))
      if parent, do: send(parent, {:chat_response, result})
    end)

    {:noreply, socket}
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("approve_tool", %{"tool_call_id" => tool_call_id}, socket) do
    parent = socket.assigns[:parent_pid]
    socket = assign(socket, :thinking, true)

    Task.start(fn ->
      result = Chat.approve_tool_call(tool_call_id)
      if parent, do: send(parent, {:chat_response, result})
    end)

    artifacts = Map.delete(socket.assigns.artifacts, tool_call_id)
    {:noreply, assign(socket, :artifacts, artifacts)}
  end

  def handle_event("reject_tool", %{"tool_call_id" => tool_call_id}, socket) do
    parent = socket.assigns[:parent_pid]
    socket = assign(socket, :thinking, true)

    Task.start(fn ->
      result = Chat.reject_tool_call(tool_call_id)
      if parent, do: send(parent, {:chat_response, result})
    end)

    artifacts = Map.delete(socket.assigns.artifacts, tool_call_id)
    {:noreply, assign(socket, :artifacts, artifacts)}
  end

  def handle_event("clear_chat", _params, socket) do
    Chat.clear_history()
    {:noreply, assign(socket, messages: [], artifacts: %{}, input: "", thinking: false)}
  end

  def handle_event("select_model", %{"model" => model}, socket) do
    config = Map.put(socket.assigns.config, "model", model)
    Ai.save_config(config)
    {:noreply, assign(socket, :config, config)}
  end

  defp load_config do
    case Ai.read_config() do
      {:ok, config} -> config
      _ -> %{}
    end
  end

  defp load_models(config) when map_size(config) > 0 do
    case Client.list_models(Map.put(config, "mock", false)) do
      {:ok, models} -> models
      _ -> []
    end
  end

  defp load_models(_), do: []

  defp humanize_tool(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp md_to_html(content) do
    case Earmark.as_html(content, compact_output: true) do
      {:ok, html, _} -> html
      _ -> content
    end
  end

  defp find_last_assistant_idx(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {%{"role" => "assistant", "content" => c}, idx} when is_binary(c) -> idx
      _ -> nil
    end)
  end
end

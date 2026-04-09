defmodule Tunneld.Servers.Ai do
  @moduledoc """
  Manages the on-disk AI configuration file (`ai.json`).

  Stores the LLM provider settings: base URL, optional API key, and
  selected model. All reads and writes go through `Tunneld.Persistence`
  for atomic file operations.

  This GenServer holds no state — it exists as a named process so the
  supervision tree can track it, but all operations read/write directly
  to disk.
  """
  use GenServer

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc false
  def init(_) do
    {:ok, %{}}
  end

  @doc """
  Read and decode the AI config file. Returns `{:ok, map}` or `{:error, reason}`.
  """
  def read_config do
    case Tunneld.Persistence.read_json(path()) do
      {:ok, data} ->
        {:ok, data}

      {:error, _reason} ->
        if mock?() do
          {:ok, Tunneld.Servers.FakeData.Ai.get_config()}
        else
          {:error, "AI not configured"}
        end
    end
  end

  @doc """
  Save the AI configuration to disk. Requires a non-empty `base_url`.
  Broadcasts config changes on the `"component:ai"` PubSub topic.
  """
  def save_config(%{"base_url" => base_url} = config) when is_binary(base_url) do
    if String.trim(base_url) == "" do
      {:error, "base_url cannot be empty"}
    else
      data =
        config
        |> Map.take(["base_url", "api_key", "model", "mock"])
        |> Map.merge(%{
          "base_url" => String.trim(base_url),
          "api_key" => Map.get(config, "api_key", ""),
          "model" => Map.get(config, "model", "")
        })
        |> Map.reject(fn {_k, v} -> is_nil(v) end)

      File.mkdir_p!(Path.dirname(path()))

      case Tunneld.Persistence.write_json(path(), data) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:ai", %{
            id: "ai",
            data: data
          })

          {:ok, data}

        {:error, reason} ->
          {:error, "Failed to save AI config: #{inspect(reason)}"}
      end
    end
  end

  def save_config(_), do: {:error, "base_url is required"}

  @doc """
  Returns `true` if the AI config file exists and has a non-empty `base_url`.
  """
  def configured? do
    if mock?() do
      true
    else
      case read_config() do
        {:ok, %{"base_url" => url}} when is_binary(url) -> String.trim(url) != ""
        _ -> false
      end
    end
  end

  @doc """
  Remove the AI config file from disk.
  """
  def clear_config do
    case File.rm(path()) do
      :ok ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:ai", %{
          id: "ai",
          data: nil
        })

        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, "Failed to clear AI config: #{inspect(reason)}"}
    end
  end

  @doc """
  Returns the filesystem path for the AI config file.
  """
  def path, do: Path.join(Tunneld.Config.fs(:root), Tunneld.Config.fs(:ai) || "ai.json")
end

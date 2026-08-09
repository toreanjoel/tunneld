defmodule Tunneld.Audit do
  @moduledoc """
  Append-only audit log for the agent API.

  Every authenticated call records: timestamp, token id, action, target, and
  result. The log is a JSON-lines file (`audit.jsonl`) under the data root —
  append-only, never rewritten in place, so it is tamper-evident in aggregate.
  """

  @doc "Record an auditable action. `fields` is a map; `ts`, `token_id` are added."
  def log(action, target, result, token_id) when is_binary(action) do
    entry =
      %{
        "ts" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "token_id" => token_id,
        "action" => action,
        "target" => target,
        "result" => result
      }

    line = Jason.encode!(entry)
    path = path()

    File.mkdir_p!(Path.dirname(path))
    File.open(path, [:append, :utf8], fn io ->
      IO.write(io, line <> "\n")
    end)

    :ok
  end

  @doc "Return all audit entries (newest last). Empty list if none."
  def list do
    case File.read(path()) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(fn l ->
          case Jason.decode(l) do
            {:ok, entry} -> entry
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp path do
    Path.join(Tunneld.Config.fs_root(), "audit.jsonl")
  end
end

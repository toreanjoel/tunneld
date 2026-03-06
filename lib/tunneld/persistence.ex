defmodule Tunneld.Persistence do
  @moduledoc """
  Safe JSON file persistence with atomic writes and backup recovery.

  Writes go to a temporary file first, then rename (atomic on the same
  filesystem). A `.bak` copy is kept so a corrupted main file can be
  recovered automatically on the next read.
  """

  @doc """
  Read and decode a JSON file. Falls back to `.bak` if the main file
  is missing or corrupted.
  """
  def read_json(path) do
    case read_and_decode(path) do
      {:ok, data} ->
        {:ok, data}

      {:error, _} ->
        backup = path <> ".bak"

        case read_and_decode(backup) do
          {:ok, data} ->
            # Restore from backup
            File.copy(backup, path)
            {:ok, data}

          error ->
            error
        end
    end
  end

  @doc """
  Encode and write JSON data safely. Creates a backup of the existing
  file before writing, and uses atomic rename to prevent partial writes.
  """
  def write_json(path, data) do
    encoded = Jason.encode!(data)
    tmp_path = path <> ".tmp"
    backup_path = path <> ".bak"

    # Backup current file if it exists
    if File.exists?(path) do
      File.copy(path, backup_path)
    end

    # Write to temp file, then atomic rename
    case File.write(tmp_path, encoded) do
      :ok ->
        File.rename(tmp_path, path)

      {:error, reason} ->
        File.rm(tmp_path)
        {:error, reason}
    end
  end

  defp read_and_decode(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          {:error, err} -> {:error, {:decode_failed, err}}
        end

      {:error, reason} ->
        {:error, {:read_failed, reason}}
    end
  end
end

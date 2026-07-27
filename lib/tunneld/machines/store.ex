defmodule Tunneld.Machines.Store do
  @moduledoc """
  On-disk persistence for the machine registry.

  Mirrors the existing atomic-JSON pattern (Tunneld.Persistence) but holds
  a single document: `%{"machines" => [record, ...]}`. Concurrent writers go
  through the Tunneld.Machines GenServer, so this module is stateless I/O.
  """

  def path do
    Path.join(Tunneld.Config.fs_root(), "machines.json")
  end

  @doc "Return all machine records (list of maps). Empty list if no file."
  def all do
    case Tunneld.Persistence.read_json(path()) do
      {:ok, %{"machines" => list}} when is_list(list) -> list
      _ -> []
    end
  end

  @doc "Fetch a single record by id."
  def get(id) do
    case Enum.find(all(), &(&1["id"] == id)) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc "Insert or replace a record by id."
  def put(record) do
    list = all()
    id = record["id"]
    updated = Enum.reject(list, &(&1["id"] == id)) ++ [record]
    Tunneld.Persistence.write_json(path(), %{"machines" => updated})
  end

  @doc "Delete a record by id."
  def delete(id) do
    updated = Enum.reject(all(), &(&1["id"] == id))
    Tunneld.Persistence.write_json(path(), %{"machines" => updated})
    :ok
  end
end
defmodule Tunneld.Servers.ExposeAllowed do
  @moduledoc """
  Manage the Quick Expose device allowlist.

  Stores a map of MAC → boolean in `expose_allowed.json` under the
  configured filesystem root. Missing file is treated as an empty map
  (all devices denied).
  """

  @doc """
  Allow a device (MAC) to use Quick Expose.
  """
  def allow(mac) when is_binary(mac) do
    path = allowed_path()
    map = read_or_empty(path)
    Tunneld.Persistence.write_json(path, Map.put(map, mac, true))
  end

  @doc """
  Revoke a device's Quick Expose permission.
  """
  def revoke(mac) when is_binary(mac) do
    path = allowed_path()
    map = read_or_empty(path)
    Tunneld.Persistence.write_json(path, Map.put(map, mac, false))
  end

  @doc """
  Check if a device is allowed to use Quick Expose.
  Returns `false` if the file is missing or the MAC is not present.
  """
  def allowed?(mac) when is_binary(mac) do
    path = allowed_path()
    map = read_or_empty(path)
    Map.get(map, mac, false)
  end

  defp allowed_path do
    Path.join(Tunneld.Config.fs_root(), "expose_allowed.json")
  end

  defp read_or_empty(path) do
    case Tunneld.Persistence.read_json(path) do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end
end

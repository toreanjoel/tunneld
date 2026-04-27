defmodule Tunneld.Servers.DeviceTags do
  @moduledoc """
  Manage custom tags/labels for devices.

  Stores a map of MAC → [tag strings] in `device_tags.json` under the
  configured filesystem root. Missing file is treated as an empty map.

  Tags persist across DHCP lease renewals and help identify devices
  that report generic hostnames like `android-12345`.
  """

  @doc """
  Add a tag to a device (MAC). Duplicate tags are ignored.
  """
  def add_tag(mac, tag) when is_binary(mac) and is_binary(tag) do
    tag = String.trim(tag)

    if tag == "" do
      :ok
    else
      path = tags_path()
      map = read_or_empty(path)
      existing = Map.get(map, mac, [])

      updated =
        if tag in existing do
          existing
        else
          [tag | existing]
        end

      Tunneld.Persistence.write_json(path, Map.put(map, mac, updated))
    end
  end

  @doc """
  Remove a tag from a device (MAC).
  """
  def remove_tag(mac, tag) when is_binary(mac) and is_binary(tag) do
    path = tags_path()
    map = read_or_empty(path)
    existing = Map.get(map, mac, [])
    updated = Enum.reject(existing, &(&1 == tag))

    if updated == [] do
      Tunneld.Persistence.write_json(path, Map.delete(map, mac))
    else
      Tunneld.Persistence.write_json(path, Map.put(map, mac, updated))
    end
  end

  @doc """
  Get all tags for a device (MAC). Returns `[]` if none.
  """
  def get_tags(mac) when is_binary(mac) do
    path = tags_path()
    map = read_or_empty(path)
    Map.get(map, mac, [])
  end

  @doc """
  Get the full tags map for all devices.
  """
  def all_tags() do
    path = tags_path()
    read_or_empty(path)
  end

  defp tags_path do
    Path.join(Tunneld.Config.fs_root(), "device_tags.json")
  end

  defp read_or_empty(path) do
    case Tunneld.Persistence.read_json(path) do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end
end

defmodule Tunneld.Config do
  @moduledoc """
  Shared configuration helpers used across multiple modules.

  Provides access to filesystem paths and other common config values
  from the `:tunneld` application environment, handling both keyword list
  and map formats for backwards compatibility.
  """

  @doc """
  Retrieve a filesystem config value (e.g., `:root`, `:auth`, `:resources`, `:sqm`).
  """
  def fs(key) do
    case Application.get_env(:tunneld, :fs) do
      kw when is_list(kw) -> Keyword.get(kw, key)
      map when is_map(map) -> Map.get(map, key) || Map.get(map, to_string(key))
      _ -> nil
    end
  end

  @doc """
  Returns the root data directory path.

  In production this is typically `/var/lib/tunneld`, in dev it's the local `data/` directory.
  """
  def fs_root do
    fs(:root) || "/var/lib/tunneld"
  end
end

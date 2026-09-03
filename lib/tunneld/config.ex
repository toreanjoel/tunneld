defmodule Tunneld.Config do
  @moduledoc """
  Shared configuration helpers used across multiple modules.

  Provides access to filesystem paths and other common config values
  from the `:tunneld` application environment, handling both keyword list
  and map formats for backwards compatibility.
  """

  @doc """
  Retrieve a filesystem config value (e.g., `:root`, `:auth`, `:resources`).
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

  @doc """
  Retrieve a `:network` config value (`:gateway`, `:upstream`, `:downstream`).

  This lived as five byte-identical private copies across `Machines`,
  `Overlay`, `Egress`, `Caddy` and `DnsConfig`. One copy, one place to fix.
  """
  def network(key) do
    case Application.get_env(:tunneld, :network, []) do
      kw when is_list(kw) -> Keyword.get(kw, key)
      map when is_map(map) -> Map.get(map, key) || Map.get(map, to_string(key))
      _ -> nil
    end
  end

  @doc "The gateway's LAN IP (the downstream interface address)."
  def gateway_ip, do: network(:gateway)

  @doc """
  Whether remote-machine features (egress/exit nodes and WireGuard clients) are
  enabled.

  These features only make sense when managed machines are reached remotely.
  In a purely local setup (one gateway, every machine on the same subnet) they
  are noise: local devices never exit through a remote VM, and a client has
  nothing to dial home to that a local box already provides.

  Defaults to `true` for backwards compatibility. Disable with the
  `TUNNELD_REMOTE_FEATURES=disabled` env var, or by setting
  `config :tunneld, :remote_features, false`.
  """
  def remote_features? do
    case Application.get_env(:tunneld, :remote_features, true) do
      false -> false
      nil -> false
      _ -> true
    end
  end
end

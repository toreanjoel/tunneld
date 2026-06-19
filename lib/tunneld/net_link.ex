defmodule Tunneld.NetLink do
  @moduledoc """
  Ethernet link state helpers for the gateway's upstream and downstream
  interfaces.

  Replaces the former `Tunneld.Servers.Wlan.connected?/0` checks. Interface
  names come from app config (`:tunneld, :network` -> `:upstream` / `:downstream`)
  and are never hardcoded here.

  Link state is read from `/sys/class/net/<iface>/operstate`:
    - `"up"`        -> connected
    - any other     -> disconnected

  In mock mode (`MOCK_DATA=true`) link state is reported from
  `Tunneld.Servers.FakeData.ethernet/0` so the dashboard stays functional in
  local development.
  """

  @operstate_path "/sys/class/net"

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  defp net_config, do: Application.get_env(:tunneld, :network, [])

  @doc "Returns the configured upstream interface name (or `nil`)."
  def upstream_iface, do: net_config()[:upstream]

  @doc "Returns the configured downstream interface name (or `nil`)."
  def downstream_iface, do: net_config()[:downstream]

  @doc """
  Returns `true` if the upstream interface reports the `"up"` operstate.

  In mock mode, returns the upstream state from `FakeData.ethernet/0`.
  Falls back to `false` on any error (missing config, missing sysfs file, etc).
  """
  def upstream_up?, do: iface_up?(:upstream)

  @doc """
  Returns `true` if the downstream interface reports the `"up"` operstate.

  In mock mode, returns the downstream state from `FakeData.ethernet/0`.
  """
  def downstream_up?, do: iface_up?(:downstream)

  @doc """
  Returns a map summarising both interfaces:

      %{
        upstream: %{iface: "eth0", up: true},
        downstream: %{iface: "eth1", up: true}
      }

  Missing interfaces report `up: false` with `iface: nil`.
  """
  def status do
    %{
      upstream: %{iface: upstream_iface(), up: upstream_up?()},
      downstream: %{iface: downstream_iface(), up: downstream_up?()}
    }
  end

  defp iface_up?(which) do
    cond do
      mock?() ->
        fake_state(which)

      iface = net_config()[which] ->
        case File.read(Path.join(@operstate_path, "#{iface}/operstate")) do
          {:ok, contents} -> String.trim(contents) == "up"
          _ -> false
        end

      true ->
        false
    end
  end

  defp fake_state(which) do
    case Tunneld.Servers.FakeData.ethernet() do
      %{^which => state} when state in ["up", :up, true] -> true
      _ -> false
    end
  rescue
    _ -> true
  end
end
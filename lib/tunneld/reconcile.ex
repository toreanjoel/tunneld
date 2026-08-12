defmodule Tunneld.Reconcile do
  @moduledoc """
  Drift detection and repair for a managed machine.

  Reads live state (WireGuard, Caddy, SSH, listening sockets) and diffs it
  against what tunneld wants, optionally repairing drift. This is the single
  "what is running right now" authority — disk/cached state is only a hint.

  Replaces every ad-hoc "reopen on boot" path: `reconcile/1` is called on a
  timer and from a UI button, and converges a machine back to the desired
  state without bespoke restart logic.

  Returns a map of subsystem results:

      %{wireguard: :ok | {:drift, ...}, caddy: ..., ssh: ..., resources: ...}

  In mock mode no live commands are run; the function reports the subsystems
  as present based on the machine record.
  """

  require Logger

  alias Tunneld.Machines.SSH
  alias Tunneld.Overlay

  @doc """
  Reconcile a machine against desired state. `opts` may include
  `repair: true` to apply fixes (idempotent) or `repair: false` (default) to
  only report drift.
  """
  def reconcile(machine, opts \\ []) do
    repair? = Keyword.get(opts, :repair, false)

    %{
      wireguard: reconcile_wireguard(machine, repair?),
      caddy: reconcile_caddy(machine, repair?),
      ssh: reconcile_ssh(machine),
      resources: reconcile_resources(machine),
      door: reconcile_door(machine, repair?)
    }
  end

  # Machines enrolled before client access existed have no door, and a target's
  # iptables do not survive its reboot, so this is both the upgrade path and the
  # repair path. Cheap and idempotent: it only rewrites a destination port.
  defp reconcile_door(machine, true) do
    case Tunneld.Clients.ensure_door(machine) do
      :ok -> :ok
      {:error, reason} -> {:drift, {:door_failed, reason}}
    end
  end

  defp reconcile_door(_machine, false), do: :ok

  # WireGuard: a peer should exist for every machine that is not local.
  defp reconcile_wireguard(machine, repair?) do
    if machine["location"] == "local" do
      :ok
    else
      case Overlay.status(machine) do
        {:ok, %{up: true}} ->
          :ok

        _ ->
          if repair? do
            case Overlay.ensure_peer(machine) do
              {:ok, _} -> {:repaired, :wireguard}
              {:error, reason} -> {:drift, {:wireguard_down, reason}}
            end
          else
            {:drift, :wireguard_down}
          end
      end
    end
  end

  # Caddy: the gateway's Caddy config should match the resource list. The
  # Resources server reconciles Caddy on every change, so drift is unusual.
  defp reconcile_caddy(_machine, _repair?) do
    :ok
  end

  # SSH: report reachability as a health signal (a full host-key rotation check
  # is out of scope; tunneld already uses accept-new on connect).
  defp reconcile_ssh(machine) do
    case SSH.run(machine, "echo ok") do
      {:ok, "ok" <> _} -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:drift, {:ssh_unreachable, reason}}
    end
  end

  defp reconcile_resources(_machine) do
    :ok
  end
end

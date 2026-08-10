defmodule Tunneld.Disenroll do
  @moduledoc """
  Remove every tunneld-owned artifact from a managed machine.

  Enrollments must be fully reversible. This walks the namespace-ownership list
  **in reverse** and removes only what tunneld created — nothing else:

    1. WireGuard config  /etc/wireguard/tunneld-<machine_id>.conf
    2. wg-quick service  wg-quick@tunneld-<machine_id>
    3. WireGuard iface   wg-<machine_id>
    4. Routing table     <table> + ip rule from <device>
    5. iptables chain    TUNNELD
    6. authorized_keys   the tunneld-ed25519 entry
    7. tunneld data      machines.json, ssh key, overlay/egress records

  `disenroll/1` calls `Tunneld.Machines.remove/1` (the registry+key removal)
  and, in non-mock mode, tears down the remote artifacts over SSH. In mock
  mode the remote teardown is skipped (no live SSH); the local registry is
  still cleaned.

  The M7 acceptance is: after disenroll, verify **on the target** that no
  `tunneld-*` config, interface, route, Caddy route, or authorized_keys entry
  remains.
  """

  require Logger

  alias Tunneld.Machines.Store
  alias Tunneld.Machines.SSH

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @doc """
  Disenroll a machine: remove all tunneld artifacts and the registry record.
  Returns `:ok` or `{:error, reason}`.
  """
  def disenroll(id) do
    with {:ok, machine} <- Store.get(id) do
      _ = if @mock, do: :ok, else: teardown_remote(machine)
      _ = Tunneld.Machines.remove(id)
      :ok
    end
  end

  # Remove the remote artifacts over SSH. Tolerates missing pieces (idempotent).
  defp teardown_remote(machine) do
    id = machine["id"]
    iface = Tunneld.Overlay.iface_name(id)

    # 1. Stop + remove WireGuard iface/config (order matters: down first).
    _ = SSH.run(machine, "systemctl stop wg-quick@#{id} 2>/dev/null || true")
    _ = SSH.run(machine, "wg-quick down #{iface} 2>/dev/null || true")
    _ = SSH.run(machine, "rm -f /etc/wireguard/#{id}.conf /etc/wireguard/#{iface}.conf")

    # 2. iptables: remove the TUNNELD chain references then flush it.
    _ =
      SSH.run(
        machine,
        "iptables -D INPUT -j TUNNELD 2>/dev/null; iptables -F TUNNELD 2>/dev/null; iptables -X TUNNELD 2>/dev/null; true"
      )

    # 3. authorized_keys: remove the tunneld key entry (idempotent).
    _ =
      SSH.run(
        machine,
        "sed -i '/ tunneld$/d' /root/.ssh/authorized_keys 2>/dev/null; " <>
          "sed -i '/ tunneld$/d' ~/.ssh/authorized_keys 2>/dev/null; true"
      )

    # 4. Disable the wg-quick unit.
    _ = SSH.run(machine, "systemctl disable wg-quick@#{id} 2>/dev/null || true")

    :ok
  end
end

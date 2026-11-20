defmodule Tunneld.Reconciler do
  @moduledoc """
  Periodic repair pass over the managed fleet.

  Everything tunneld depends on outside its own process is runtime state: the
  gateway's `ip rule`s and policy tables, the exit node's NAT and FORWARD rules,
  its per-device return routes. Each of those disappears when the box that holds
  it restarts, and only the "Reconcile" button used to put them back. A VM that
  reboots an hour after the gateway was therefore broken until someone noticed
  and clicked - which is what made re-enrolling a machine look like the only way
  out.

  One timer closes that gap: re-assert the gateway's own egress rules (cheap and
  local), then run a repairing reconcile over machines that could have lost
  state. Every action in the pass is idempotent, so running it forever is safe.
  """

  use GenServer

  require Logger

  @interval_ms 5 * 60 * 1000

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if enabled?() do
      schedule()
    end

    {:ok, %{}}
  end

  @doc "Run one pass now (also what the boot sequence calls)."
  def pass, do: do_pass()

  @impl true
  def handle_info(:tick, state) do
    do_pass()
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, @interval_ms)

  # Mock mode drives no real networking, and there is nothing to converge.
  defp enabled?, do: not Application.get_env(:tunneld, :mock_data, false)

  defp do_pass do
    Tunneld.Egress.restore_all()

    Tunneld.Machines.list()
    |> Enum.filter(&worth_reconciling?/1)
    |> Enum.each(fn machine ->
      try do
        _ = Tunneld.Reconcile.reconcile(machine, repair: true)
      rescue
        e -> Logger.warning("Reconcile pass failed for #{machine["id"]}: #{Exception.message(e)}")
      end
    end)

    # A second time, and *after* the loop, because the loop itself can break the
    # gateway's egress: repairing a WireGuard peer restarts wg-quick@<iface>, and
    # that deletes the policy table's default route. Restoring only before the
    # loop meant every pass undid the previous one.
    Tunneld.Egress.restore_all()
  end

  # Only machines whose setup can actually drift. A plain LAN machine that is
  # neither an exit node nor a client door holds no runtime state of ours, so it
  # would cost an SSH round trip for nothing.
  @doc false
  def worth_reconciling?(machine) do
    Tunneld.Egress.exit_capable?(machine) or machine["location"] == "remote" or
      Tunneld.Clients.for_machine(machine["id"]) != []
  end
end

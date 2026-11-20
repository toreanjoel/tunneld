defmodule Tunneld.ReconcilerTest do
  use ExUnit.Case, async: false

  alias Tunneld.Machines

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_reconciler_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  test "a pass repairs an exit node's rules without any operator action" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps", "address" => "203.0.113.9", "location" => "remote"})

    {:ok, m} = Machines.get(id)
    {:ok, _} = Tunneld.Egress.ensure_exit_capable(m)
    {:ok, _} = Tunneld.Egress.route_device(m, "10.0.0.60")

    assert :ok = Tunneld.Reconciler.pass()
    # the pass must not undo what was there
    assert Tunneld.Egress.exit_capable?(m)
    assert Tunneld.Egress.device_egress("10.0.0.60") == id
  end

  test "a plain local machine is left alone" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "nas", "address" => "10.0.0.9", "location" => "local"})

    {:ok, m} = Machines.get(id)
    refute Tunneld.Reconciler.worth_reconciling?(m)
    assert :ok = Tunneld.Reconciler.pass()
    assert Machines.get(id) == {:ok, m}
  end
end

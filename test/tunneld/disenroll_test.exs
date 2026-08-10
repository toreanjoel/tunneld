defmodule Tunneld.DisenrollTest do
  use ExUnit.Case, async: false

  alias Tunneld.Machines
  alias Tunneld.Disenroll

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_disenroll_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  test "disenroll removes the machine from the registry" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps", "address" => "203.0.113.9", "location" => "remote"})

    assert {:ok, _} = Machines.get(id)
    assert :ok = Disenroll.disenroll(id)
    assert {:error, :not_found} = Machines.get(id)
  end

  test "disenroll is idempotent-ish (unknown id returns error)" do
    assert {:error, :not_found} = Disenroll.disenroll("nope")
  end

  test "disenroll removes the ssh key files" do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps2", "address" => "203.0.113.10", "location" => "remote"})

    ssh_dir = Path.join(Application.get_env(:tunneld, :fs)[:root], "ssh")
    assert File.exists?(Path.join(ssh_dir, id))
    Disenroll.disenroll(id)
    refute File.exists?(Path.join(ssh_dir, id))
  end
end

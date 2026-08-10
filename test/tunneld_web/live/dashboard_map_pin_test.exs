defmodule TunneldWeb.Live.DashboardMapPinTest do
  @moduledoc """
  Regression: deleting a machine left its pin on the map until a full page
  refresh. The map was fed by `nodes={map_nodes()}` - an expression referencing
  no assigns, so LiveView change tracking never re-evaluated it.
  """
  use TunneldWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Tunneld.Machines
  alias Tunneld.Servers.Session

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_mappin_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    client_id = "test-client-#{System.unique_integer([:positive])}"
    Session.create(client_id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{"client_id" => client_id})

    {:ok, conn: conn}
  end

  test "removing a remote machine drops its map pin without a page refresh", %{conn: conn} do
    {:ok, %{"id" => id}} =
      Machines.enroll(%{
        "name" => "berlin-vm",
        "address" => "203.0.113.9",
        "location" => "remote"
      })

    {:ok, view, _html} = live(conn, "/dashboard")

    assert render(view) =~ "berlin-vm", "pin should be on the map after enrolling"

    # Remove the machine the same way the app does. The removal broadcast is
    # delivered asynchronously, so synchronise on the LiveView process before
    # rendering: :sys.get_state/1 is handled only after every message already
    # queued in its mailbox, which makes this deterministic rather than racy.
    Machines.remove(id)
    _ = :sys.get_state(view.pid)

    html = render(view)

    refute html =~ "berlin-vm",
           "map pin must disappear on the live view, without needing a refresh"
  end
end

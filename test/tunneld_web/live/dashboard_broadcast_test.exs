defmodule TunneldWeb.Live.DashboardBroadcastTest do
  @moduledoc """
  Regression: the dashboard handled every broadcast twice.

  A LiveComponent's mount/1 runs in the PARENT LiveView process. The dashboard
  already subscribes to component:machines, component:resources and
  component:system_resources, and three components subscribed again from their
  own mount/1, so one process held two identical subscriptions per topic and
  did the work for each broadcast twice.
  """
  use TunneldWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Tunneld.Servers.Session

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_bcast_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev = Application.get_env(:tunneld, :fs, [])
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, prev)
    end)

    client_id = "test-client-#{System.unique_integer([:positive])}"
    Session.create(client_id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{"client_id" => client_id})

    {:ok, conn: conn}
  end

  test "each component topic is subscribed exactly once per dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")

    for topic <- ["component:machines", "component:resources", "component:system_resources"] do
      subscribers =
        Registry.lookup(Tunneld.PubSub, topic)
        |> Enum.filter(fn {pid, _} -> pid == view.pid end)

      assert length(subscribers) == 1,
             "#{topic}: the dashboard process holds #{length(subscribers)} subscriptions, " <>
               "so every broadcast on it is handled that many times"
    end
  end
end

defmodule TunneldWeb.Live.DashboardSessionRenewalTest do
  @moduledoc """
  Regression: the terminal reported "Socket connection failed" on a dashboard
  that was otherwise working.

  The auth session is in-memory and TTL'd, and it was renewed on LiveView mount
  only. A LiveView mounts once and then lives for hours, so an operator who kept
  the tab open let the session lapse: every LiveView interaction still worked
  (events are not auth-checked once mounted) while the exec socket, which
  validates the session at connect, answered 403 - which the browser can only
  report as a failed socket.

  Interaction now renews. An idle tab still expires on schedule.
  """
  use TunneldWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Tunneld.Servers.Session
  alias TunneldWeb.UserSocket

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_renewal_#{System.unique_integer([:positive])}")
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

    {:ok, conn: conn, client_id: client_id}
  end

  test "using the dashboard renews the session the exec socket authenticates against", %{
    conn: conn,
    client_id: client_id
  } do
    {:ok, view, _html} = live(conn, "/dashboard")

    # The store has no clock to inject, so age the session by hand instead of
    # sleeping out a real TTL: one second left, still valid, about to lapse.
    deadline = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(1)
    :sys.replace_state(Session, &Map.put(&1, client_id, %{expires_at: deadline}))

    render_click(view, "toggle_devices_expanded")

    assert {:ok, %{expires_at: renewed}} = Session.get(client_id)

    assert renewed > deadline,
           "interacting with the dashboard must push the session deadline out"

    assert {:ok, _socket} =
             Phoenix.ChannelTest.__connect__(@endpoint, UserSocket, %{},
               connect_info: %{session: %{"client_id" => client_id}}
             )
  end
end

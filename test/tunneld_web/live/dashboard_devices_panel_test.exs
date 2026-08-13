defmodule TunneldWeb.Live.DashboardDevicesPanelTest do
  @moduledoc """
  Regression: opening "View all devices" showed "Scanning Devices..." even
  though the devices server already held a current list.

  The parent renders the component with no `:data` assign - the payload only
  arrives on the next broadcast - and update/2 defaulted that to `%{}`, emptying
  the list and flipping the panel back into its loading state on every open.
  """
  use TunneldWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Tunneld.Servers.Devices
  alias Tunneld.Servers.Session

  setup do
    # An empty fs root means Auth.read_file/0 errors, which is the "already
    # onboarded" path - the same trick the other dashboard LiveView tests use.
    tmp = Path.join(System.tmp_dir!(), "tunneld_devices_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    client_id = "test-client-#{System.unique_integer([:positive])}"
    Session.create(client_id)

    # Make sure the server has read the (mock) leases at least once, which is
    # the state the panel is opened in on a running gateway.
    Devices.sync_now()
    _ = :sys.get_state(Devices)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{"client_id" => client_id})

    {:ok, conn: conn}
  end

  test "the panel paints the cached devices on open, without a scanning state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")

    html = render_click(view, "toggle_devices_expanded")

    refute html =~ "Scanning Devices...",
           "the devices server already has a list; the panel must not claim to be scanning"

    assert html =~ "Person1Person1Person1Person1", "the cached devices should be on screen"
  end

  test "opening the panel asks the devices server for a fresh read", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")

    Phoenix.PubSub.subscribe(Tunneld.PubSub, "component:devices")

    render_click(view, "toggle_devices_expanded")

    assert_receive %{id: "devices", data: %{devices: _}}, 1_000
  end
end

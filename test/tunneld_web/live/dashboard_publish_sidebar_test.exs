defmodule TunneldWeb.Live.DashboardPublishSidebarTest do
  @moduledoc """
  Regression: publishing a resource left the open sidebar showing "Publish" and
  none of the public-access detail until it was closed and reopened.

  Twice, in fact. The first fix wired a refresh into the *unpublish* handler
  only - publishing takes a different path (a modal form -> `publish:steps`
  broadcast) which never refreshed anything. These tests drive both paths.
  """
  use TunneldWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Tunneld.{Machines, Publish}
  alias Tunneld.Servers.{Resources, Session}

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_pubsidebar_#{System.unique_integer([:positive])}")
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

    {:ok, %{"id" => machine_id}} =
      Machines.enroll(%{
        "name" => "berlin-vm",
        "address" => "203.0.113.9",
        "location" => "remote"
      })

    Resources.add_share(%{"name" => "printer", "description" => "d", "pool" => ["10.0.0.5:80"]})
    resource = wait_for_resource("printer")

    {:ok, conn: conn, machine_id: machine_id, resource: resource}
  end

  defp wait_for_resource(name, tries \\ 50) do
    case Enum.find(Resources.fetch_shares(), &(&1.name == name)) do
      nil when tries > 0 -> Process.sleep(20) && wait_for_resource(name, tries - 1)
      found -> found
    end
  end

  # The panel loads its data via a cast -> PubSub -> send_update round trip, so
  # the first render after the click is still empty.
  defp eventually(view, needle, tries \\ 60) do
    html = render(view)

    cond do
      html =~ needle -> html
      tries == 0 -> flunk("never rendered #{inspect(needle)}")
      true -> Process.sleep(25) && eventually(view, needle, tries - 1)
    end
  end

  defp eventually_absent(view, needle, tries \\ 60) do
    html = render(view)

    cond do
      not (html =~ needle) -> html
      tries == 0 -> flunk("#{inspect(needle)} never went away")
      true -> Process.sleep(25) && eventually_absent(view, needle, tries - 1)
    end
  end

  defp open_resource_panel(view, id) do
    render_click(view, "show_details", %{"id" => id, "type" => "resource"})
    eventually(view, "printer")
  end

  test "publishing updates the open sidebar without reopening it", %{
    conn: conn,
    machine_id: machine_id,
    resource: resource
  } do
    {:ok, view, _html} = live(conn, "/dashboard")
    html = open_resource_panel(view, resource.id)

    assert html =~ "Publish"
    refute html =~ "Unpublish"
    refute html =~ "203.0.113.9:8001"

    {:ok, machine} = Machines.get(machine_id)
    {:ok, _rec} = Publish.publish(%{"id" => resource.id, "name" => resource.name}, machine, 8001)

    # exactly what dashboard/actions.ex broadcasts after a successful publish
    send(view.pid, {:publish_steps, resource.id, Publish.get(resource.id)})

    html = eventually(view, "Unpublish")
    assert html =~ "http://203.0.113.9:8001", "public URL missing from the open sidebar"
  end

  test "unpublishing updates the open sidebar without reopening it", %{
    conn: conn,
    machine_id: machine_id,
    resource: resource
  } do
    {:ok, machine} = Machines.get(machine_id)
    {:ok, _} = Publish.publish(%{"id" => resource.id, "name" => resource.name}, machine, 8001)

    {:ok, view, _html} = live(conn, "/dashboard")
    html = open_resource_panel(view, resource.id)
    assert html =~ "Unpublish"
    assert html =~ "http://203.0.113.9:8001"

    render_click(view, "unpublish_resource", %{"id" => resource.id})

    html = eventually_absent(view, "Unpublish")
    refute html =~ "http://203.0.113.9:8001"
  end
end

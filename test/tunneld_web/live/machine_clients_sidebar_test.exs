defmodule TunneldWeb.Live.MachineClientsSidebarTest do
  @moduledoc """
  Regression: adding or revoking a client left the machine panel showing the
  old list until it was closed and reopened. Third time this class of bug has
  appeared (map pins, publish toggle, now clients), so it gets a test that
  drives the real LiveView rather than the module underneath it.
  """
  use TunneldWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Tunneld.{Clients, Machines}
  alias Tunneld.Servers.Session

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_mclients_#{System.unique_integer([:positive])}")
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

    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "za-box", "address" => "203.0.113.9", "location" => "remote"})

    {:ok, conn: conn, machine_id: id}
  end

  defp settle(view, needle, tries \\ 60) do
    html = render(view)

    cond do
      html =~ needle -> html
      tries == 0 -> flunk("never rendered #{inspect(needle)}")
      true -> Process.sleep(25) && settle(view, needle, tries - 1)
    end
  end

  defp gone(view, needle, tries \\ 60) do
    html = render(view)

    cond do
      not (html =~ needle) -> html
      tries == 0 -> flunk("#{inspect(needle)} never went away")
      true -> Process.sleep(25) && gone(view, needle, tries - 1)
    end
  end

  test "adding and revoking a client updates the open machine panel", %{
    conn: conn,
    machine_id: machine_id
  } do
    {:ok, view, _} = live(conn, "/dashboard")
    render_click(view, "show_details", %{"id" => machine_id, "type" => "machine"})
    settle(view, "za-box")

    render_submit(view, "enroll_client", %{"machine_id" => machine_id, "name" => "partner-phone"})
    html = settle(view, "revoke_client")
    assert html =~ "partner-phone"
    assert html =~ "10.88.1.", "the client's overlay address should be listed"

    [client] = Clients.for_machine(machine_id)

    # granting access updates the panel in place, and clearing it revokes.
    # Driven through the modal action pipeline, which is what the UI uses.
    grant = fn ips ->
      Clients.set_lan_access(client["id"], ips)
      send(view.pid, {:client_access_changed, machine_id})
    end

    grant.(["10.0.0.50"])
    assert settle(view, "1 device(s)") =~ "partner-phone"

    grant.([])
    assert settle(view, "overlay only")

    render_click(view, "dismiss_issued_client", %{})
    render_click(view, "revoke_client", %{"id" => client["id"]})

    # assert on the list entry, not the name: the name also appears in the
    # transient flash, which would make this pass for the wrong reason
    html = gone(view, "revoke_client")
    refute html =~ "scan or copy, once", "the issued config block must clear too"
    assert Clients.for_machine(machine_id) == []
  end
end

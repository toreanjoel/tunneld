defmodule Tunneld.PublishTest do
  # Publishing exists to survive one specific failure: the operator forgets the
  # provider firewall and the UI claims success anyway. So the tests pin the
  # config shape (proxy at the GATEWAY, not the pool) and the honesty of status.
  use ExUnit.Case, async: false

  alias Tunneld.{Machines, Publish}

  setup do
    root = Path.join(System.tmp_dir!(), "publish_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    prev = Application.get_env(:tunneld, :fs)
    Application.put_env(:tunneld, :fs, root: root, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      if prev, do: Application.put_env(:tunneld, :fs, prev)
      File.rm_rf(root)
    end)

    {:ok, %{"id" => id}} =
      Machines.enroll(%{"name" => "vps", "address" => "203.0.113.9", "location" => "remote"})

    {:ok, machine} = Machines.get(id)
    %{machine: machine, resource: %{"id" => "r1", "name" => "printer"}}
  end

  test "publishing records the public URL and the machine fronting it", %{
    machine: m,
    resource: r
  } do
    assert {:ok, rec} = Publish.publish(r, m, 8001)

    assert rec["url"] == "http://203.0.113.9:8001"
    assert rec["machine_id"] == m["id"]
    assert rec["lan_host"] == "printer.tunneld.lan"
    assert Publish.get("r1")["port"] == 8001
  end

  # The removed implementation pointed the remote Caddy straight at the LAN
  # pool, which the gateway's FORWARD DROP would have silently eaten. The
  # upstream must be the gateway's Caddy, with Host set so its route matches.
  test "the remote server proxies to the gateway, not to the resource pool", %{
    machine: m,
    resource: r
  } do
    {:ok, _} = Publish.publish(r, m, 8001)
    config = Publish.build_config(Publish.for_machine(m["id"]))

    server = config["apps"]["http"]["servers"]["pub_r1"]
    assert server["listen"] == [":8001"]

    [%{"handle" => [proxy]}] = server["routes"]
    assert proxy["upstreams"] == [%{"dial" => "10.88.0.1:18000"}]
    assert proxy["headers"]["request"]["set"]["Host"] == ["printer.tunneld.lan"]
  end

  # A remote admin API is remote config execution, and the previous attempt
  # locked the gateway out by moving the admin listener. It stays off.
  test "the remote Caddy admin API is disabled", %{machine: m, resource: r} do
    {:ok, _} = Publish.publish(r, m, 8001)
    config = Publish.build_config(Publish.for_machine(m["id"]))

    assert config["admin"] == %{"disabled" => true}
  end

  test "a machine can front several resources at once", %{machine: m, resource: r} do
    {:ok, _} = Publish.publish(r, m, 8001)
    {:ok, _} = Publish.publish(%{"id" => "r2", "name" => "wiki"}, m, 8002)

    servers = Publish.build_config(Publish.for_machine(m["id"]))["apps"]["http"]["servers"]
    assert map_size(servers) == 2
    assert servers["pub_r2"]["listen"] == [":8002"]
  end

  test "unpublishing removes the record and its server", %{machine: m, resource: r} do
    {:ok, _} = Publish.publish(r, m, 8001)
    :ok = Publish.unpublish("r1", m)

    assert Publish.get("r1") == nil
    assert Publish.build_config(Publish.for_machine(m["id"]))["apps"]["http"]["servers"] == %{}
  end

  test "a bad port is refused rather than written into a config", %{machine: m, resource: r} do
    assert {:error, :invalid_port} = Publish.publish(r, m, 0)
    assert {:error, :invalid_port} = Publish.publish(r, m, "not-a-port")
    assert Publish.get("r1") == nil
  end

  test "port accepts a string, because that is what an HTML form sends", %{
    machine: m,
    resource: r
  } do
    assert {:ok, rec} = Publish.publish(r, m, "8001")
    assert rec["port"] == 8001
  end

  test "status starts pending and verify stamps a checked time", %{machine: m, resource: r} do
    {:ok, rec} = Publish.publish(r, m, 8001)
    assert rec["status"] == "pending"
    assert rec["last_checked"] == nil

    assert {:ok, checked} = Publish.verify("r1")
    assert checked["status"] in ["live", "unreachable"]
    assert checked["last_checked"] != nil
  end

  test "verify on an unpublished resource is an error, not a false negative" do
    assert {:error, :not_published} = Publish.verify("nope")
  end

  # The provider firewall is the one step tunneld cannot do, so it must be
  # stated, with the port and address in it - not left as a generic hint.
  test "manual steps name the port and address the operator must open", %{
    machine: m,
    resource: r
  } do
    {:ok, rec} = Publish.publish(r, m, 8001)
    steps = Publish.manual_steps(rec)
    text = Enum.map_join(steps, " ", & &1["code"])
    titles = Enum.map_join(steps, " ", & &1["title"])

    # the port and the machine, named concretely enough to act on
    assert text =~ "8001"
    assert text =~ "203.0.113.9"
    assert text =~ "http://203.0.113.9:8001"

    # the provider step must be first and must say it cannot be done here
    assert hd(steps)["title"] =~ "CLOUD PROVIDER"
    assert hd(steps)["code"] =~ "SSH cannot change it"

    # a command the operator can actually run to check for themselves
    assert text =~ "curl -v http://203.0.113.9:8001"

    # and what was already done on their behalf, so nothing looks unexplained
    assert titles =~ "ALREADY DONE"
    assert text =~ "ufw allow 8001/tcp"
  end
end

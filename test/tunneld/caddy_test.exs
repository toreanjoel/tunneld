defmodule Tunneld.CaddyTest do
  use ExUnit.Case, async: false

  alias Tunneld.Caddy
  alias Tunneld.Servers.Resources

  setup do
    tmp = Path.join(System.tmp_dir!(), "tunneld_caddy_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_root = Application.get_env(:tunneld, :fs, []) |> Keyword.get(:root)
    Application.put_env(:tunneld, :fs, root: tmp, auth: "auth.json", resources: "resources.json")

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:tunneld, :fs, root: prev_root)
    end)

    :ok
  end

  defp mock_config_file do
    Path.join(Application.get_env(:tunneld, :fs)[:root], "caddy/config.json")
  end

  defp decode_mock do
    Jason.decode!(File.read!(mock_config_file()))
  end

  test "lan_hostname and public_port" do
    assert Caddy.lan_hostname("printer") == "printer.tunneld.lan"
    assert Caddy.lan_domain() == "tunneld.lan"
    assert Caddy.public_port() == 18000
  end

  test "sync writes a mock config with a LAN server and host-matched route" do
    assert :ok = Caddy.sync([%{"id" => "1", "name" => "web", "pool" => ["10.0.0.5:3000"]}])
    config = decode_mock()

    servers = config["apps"]["http"]["servers"]
    assert servers["tunneld_lan"]["listen"] == [":18000"]
    # auto-HTTPS must be off so Caddy does not try to bind :80 (owned by tunneld)
    assert servers["tunneld_lan"]["automatic_https"] == %{"disable" => true}

    [route] = servers["tunneld_lan"]["routes"]
    assert route["match"] == [%{"host" => ["web.tunneld.lan"]}]
    assert [%{"handler" => "reverse_proxy", "upstreams" => [%{"dial" => "10.0.0.5:3000"}]}] =
             route["handle"]
  end

  test "sync generates a per-resource loopback server with no host matcher" do
    assert :ok =
             Caddy.sync([
               %{"id" => "r1", "name" => "app", "pool" => ["127.0.0.1:8080"], "loopback_port" => 20_001}
             ])

    config = decode_mock()
    servers = config["apps"]["http"]["servers"]

    loop = servers["tunneld_r1_loop"]
    assert loop["listen"] == ["#{Caddy.gateway_ip()}:20001"]
    assert loop["automatic_https"] == %{"disable" => true}
    # No host matcher: the route has no "match" key
    [route] = loop["routes"]
    refute Map.has_key?(route, "match")
    assert [%{"handler" => "reverse_proxy"}] = route["handle"]
  end

  test "adding a resource via Resources allocates a loopback port and reconciles caddy" do
    _ = Resources.add_share(%{"name" => "api", "pool" => ["10.0.0.9:9000"]})

    [r] = Resources.fetch_shares()
    assert r.loopback_port in 20_000..30_000
    assert r.name == "api"
    assert r.lan_url =~ "api.tunneld.lan"

    config = decode_mock()
    assert config["apps"]["http"]["servers"]["tunneld_#{r.id}_loop"]["listen"] ==
             ["#{Caddy.gateway_ip()}:#{r.loopback_port}"]
  end

  test "removing a resource reconciles the loopback server away" do
    _ = Resources.add_share(%{"name" => "tmp", "pool" => ["10.0.0.1:8080"]})
    [r] = Resources.fetch_shares()
    Resources.remove_share(r.id)

    assert wait_until(fn -> Resources.fetch_shares() == [] end)

    config = decode_mock()
    refute Map.has_key?(config["apps"]["http"]["servers"], "tunneld_#{r.id}_loop")
  end


  test "build_public_config: plain port listen -> no host matcher, TLS disabled" do
    config = Caddy.build_public_config([
      %{"id" => "r9", "name" => "web", "listen" => "8080", "pool" => ["127.0.0.1:3000"]}
    ])
    server = config["apps"]["http"]["servers"]["tunneld_r9_public"]
    assert server["listen"] == [":8080"]
    [route] = server["routes"]
    refute Map.has_key?(route, "match")
    assert server["automatic_https"] == %{"disable" => true}
  end

  test "build_public_config: hostname listen -> host matcher + auto TLS (no disable)" do
    config = Caddy.build_public_config([
      %{"id" => "r10", "name" => "web", "listen" => "app.example.com", "pool" => ["127.0.0.1:3000"]}
    ])
    server = config["apps"]["http"]["servers"]["tunneld_r10_public"]
    assert server["listen"] == [":80", ":443"]
    [route] = server["routes"]
    assert route["match"] == [%{"host" => ["app.example.com"]}]
    refute Map.has_key?(server, "automatic_https")
  end

  test "sync_public writes a remote-machine config in mock mode" do
    machine = %{"id" => "m1", "address" => "203.0.113.5", "location" => "remote"}
    assert :ok = Caddy.sync_public(machine, [
      %{"id" => "r11", "name" => "x", "listen" => "9090", "pool" => ["127.0.0.1:4000"]}
    ])
    path = Path.join(Application.get_env(:tunneld, :fs)[:root], "caddy/public_m1.json")
    assert File.exists?(path)
    config = Jason.decode!(File.read!(path))
    assert config["apps"]["http"]["servers"]["tunneld_r11_public"]["listen"] == [":9090"]
  end

  defp wait_until(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries <= 0 -> fun.()
      true ->
        Process.sleep(20)
        wait_until(fun, tries - 1)
    end
  end
end

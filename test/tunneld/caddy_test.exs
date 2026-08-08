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
    assert loop["listen"] == ["127.0.0.1:20001"]
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
             ["127.0.0.1:#{r.loopback_port}"]
  end

  test "removing a resource reconciles the loopback server away" do
    _ = Resources.add_share(%{"name" => "tmp", "pool" => ["10.0.0.1:8080"]})
    [r] = Resources.fetch_shares()
    Resources.remove_share(r.id)

    assert wait_until(fn -> Resources.fetch_shares() == [] end)

    config = decode_mock()
    refute Map.has_key?(config["apps"]["http"]["servers"], "tunneld_#{r.id}_loop")
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

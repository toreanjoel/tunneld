defmodule Tunneld.Caddy do
  @moduledoc """
  Drives Caddy as the gateway's reverse proxy / load balancer.

  Replaces the former `Tunneld.Servers.Nginx`. Caddy is a single static
  binary configured entirely through its JSON admin API — there is no config
  template, no `sites-available` symlink dance, and no reload signal. Config
  changes are `PUT` against the admin endpoint and are atomic.

  ## Three planes (kept distinct)

  * **LAN** — one server listens on `0.0.0.0:18000` and routes by Host header
    (`<name>.tunneld.lan`). This is the subnet plane: dnsmasq resolves
    `*.tunneld.lan` to the gateway, Caddy fronts every resource.
  * **Loopback** — every resource also gets its own server bound to a unique
    `127.0.0.1:2xxxx` with **no host matcher**, pointing at the same backend
    pool. Tools like zrok / cloudflared / ngrok / manual `ssh -L` forwards do
    not send the `tunneld.lan` Host header, so they would hit the wrong
    backend or none; the loopback listener lets them target a fixed local
    port instead.
  * **Public (remote)** — for resources on a remote machine, tunneld drives
    the **machine's own Caddy** admin API (at `http://<overlay_ip>:2019` over
    WireGuard) to expose the service on the public internet. The resource's
    `listen` field is a single object: `"8080"` (plain port, no domain/TLS)
    or `"app.example.com"` (domain — Caddy auto-provisions TLS). Same object,
    one field, no migration: pointing DNS and changing `listen` is all it
    takes.

  Config is a single global JSON document, so the module exposes
  `sync/1` which reconciles the **entire** config from the full resource list
  (idempotent — re-running converges to the same state). This replaces the
  old per-resource `upsert`/`remove` calls.

  In mock mode (`MOCK_DATA=true`) there is no Caddy binary; the generated
  config is written to `data/caddy/config.json` so the full flow runs on a
  laptop.
  """

  require Logger

  alias Tunneld.Config

  @public_port 18000
  @lan_domain "tunneld.lan"
  @admin_url "http://127.0.0.1:2019/"
  @loopback_start 20_000
  @loopback_end 30_000

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false) in [true, "true"]

  @doc "The gateway's LAN IP (the downstream interface address)."
  def gateway_ip do
    case Application.get_env(:tunneld, :network, []) do
      kw when is_list(kw) -> Keyword.get(kw, :gateway)
      map when is_map(map) -> Map.get(map, :gateway) || Map.get(map, "gateway")
      _ -> nil
    end
  end

  @doc "The LAN domain used for resource DNS names."
  def lan_domain, do: @lan_domain

  @doc "The port the LAN Caddy server listens on for resource traffic."
  def public_port, do: @public_port

  @doc "The loopback port allocation range for per-resource listeners."
  def loopback_start, do: @loopback_start
  def loopback_end, do: @loopback_end

  @doc """
  Build the local DNS hostname for a resource name (e.g. `"printer"` ->
  `"printer.tunneld.lan"`).
  """
  def lan_hostname(name) when is_binary(name) do
    "#{name}.#{@lan_domain}"
  end

  @doc """
  Reconcile Caddy's config to match the given resource list. `resources` is
  the **full** set of persisted resources (each with `"id"`, `"name"`,
  `"pool"`, and an optional `"loopback_port"`).

  Idempotent: re-running with the same resources converges to the same
  config. Returns `:ok` or `{:error, reason}`.
  """
  def sync(resources) when is_list(resources) do
    config = build_config(resources)

    if mock?() do
      write_mock(config)
    else
      push_config(config)
    end
  end

  @doc """
  Build the full Caddy JSON config document for the given resource list.
  Exposed for testing.
  """
  def build_config(resources) do
    lan_routes =
      Enum.map(resources, fn r ->
        %{
          "match" => [%{"host" => [lan_hostname(r["name"])]}],
          "handle" => [reverse_proxy(r["pool"])]
        }
      end)

    loop_servers =
      resources
      |> Enum.reject(&(r_empty(&1["loopback_port"])))
      |> Map.new(fn r -> {loop_server_name(r["id"]), loop_server(r)} end)

    %{
      "admin" => %{"listen" => "127.0.0.1:2019"},
      "apps" => %{
        "http" => %{
          "servers" =>
            Map.merge(
              %{
                "tunneld_lan" => %{
                  "listen" => [":#{@public_port}"],
                  "routes" => lan_routes,
                  "automatic_https" => %{"disable" => true}
                }
              },
              loop_servers
            )
        }
      }
    }
  end

  @doc """
  Return the loopback listener server name for a resource id.
  """
  def loop_server_name(id), do: "tunneld_#{id}_loop"

  @doc """
  Build a Caddy config for a **remote machine's** public exposure. This drives
  the machine's own Caddy admin API (over WireGuard) so a service is reachable
  on the public internet without a tunneld-side tunnel.

  `listen` is a single object: `"8080"` (plain port, no domain/TLS) or
  `"app.example.com"` (domain — Caddy auto-provisions TLS). Returns a full
  Caddy JSON document.
  """
  def build_public_config(resources) when is_list(resources) do
    servers =
      resources
      |> Enum.reject(&(r_empty(&1["listen"])))
      |> Map.new(fn r -> {public_server_name(r["id"]), public_server(r)} end)

    %{
      "admin" => %{"listen" => "127.0.0.1:2019"},
      "apps" => %{"http" => %{"servers" => servers}}
    }
  end

  @doc "Return the public server name for a resource id."
  def public_server_name(id), do: "tunneld_#{id}_public"

  @doc """
  Drive a remote machine's Caddy admin API (at `http://<overlay_ip>:2019`,
  reached over the WireGuard overlay) to apply a public-exposure config.
  Returns `:ok` or `{:error, reason}`. In mock mode, writes to disk.
  """
  def sync_public(machine, resources) when is_list(resources) do
    config = build_public_config(resources)

    if mock?() do
      dir = Path.join(Config.fs_root(), "caddy")
      File.mkdir_p!(dir)
      File.write(Path.join(dir, "public_#{machine["id"]}.json"), Jason.encode!(config, pretty: true))
    else
      overlay_ip = Tunneld.Overlay.address_for(machine)
      push_config(config, "http://#{overlay_ip}:2019/")
    end
  end

  # --- config building ---

  defp reverse_proxy(pool) do
    upstreams =
      pool
      |> Enum.reject(&(r_empty(&1)))
      |> Enum.map(fn entry ->
        case String.split(entry, ":", parts: 2) do
          [ip, port] -> %{"dial" => "#{ip}:#{port}"}
          _ -> %{"dial" => entry}
        end
      end)

    %{"handler" => "reverse_proxy", "upstreams" => upstreams}
  end

  defp loop_server(r) do
    # Bind to the gateway's LAN IP (not just loopback) so the no-host-matcher
    # listener is reachable from any machine on the subnet — e.g. a zrok /
    # cloudflared instance running on another box can share
    # http://<gateway-ip>:<port> without tunneld knowing anything about it.
    bind = gateway_ip() || "127.0.0.1"

    %{
      "listen" => ["#{bind}:#{r["loopback_port"]}"],
      "routes" => [%{"handle" => [reverse_proxy(r["pool"])]}],
      "automatic_https" => %{"disable" => true}
    }
  end

  # Build the public server for a remote machine's Caddy.
  #   listen == "8080"        -> :8080, no host matcher, TLS disabled
  #   listen == "app.example" -> :80/:443, host matcher, TLS auto (default)
  defp public_server(r) do
    listen = r["listen"]

    if Regex.match?(~r/^\d+$/, listen) do
      %{
        "listen" => [":#{listen}"],
        "routes" => [%{"handle" => [reverse_proxy(r["pool"])]}],
        "automatic_https" => %{"disable" => true}
      }
    else
      %{
        "listen" => [":80", ":443"],
        "routes" => [
          %{
            "match" => [%{"host" => [String.trim(listen)]}],
            "handle" => [reverse_proxy(r["pool"])]
          }
        ]
      }
    end
  end

  defp r_empty(nil), do: true
  defp r_empty(""), do: true
  defp r_empty(_), do: false

  # --- apply ---

  defp push_config(config), do: push_config(config, @admin_url)

  defp push_config(config, base_url) do
    body = Jason.encode!(config)

    # POST /load atomically replaces the entire config (the recommended way to
    # load a full new config). PUT /config/ would 409 when a config already
    # exists.
    case HTTPoison.post(
           base_url <> "load",
           body,
           [{"content-type", "application/json"}],
           timeout: 10_000,
           recv_timeout: 10_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        Logger.error("Caddy config rejected (#{code}): #{inspect(resp_body)}")
        {:error, {:caddy_http, code, resp_body}}

      {:error, reason} ->
        Logger.error("Caddy admin API unreachable: #{inspect(reason)}")
        {:error, {:caddy_http, reason}}
    end
  end

  defp write_mock(config) do
    dir = Path.join(Config.fs_root(), "caddy")
    File.mkdir_p!(dir)
    File.write(Path.join(dir, "config.json"), Jason.encode!(config, pretty: true))
  end
end

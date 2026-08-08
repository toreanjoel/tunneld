defmodule Tunneld.Caddy do
  @moduledoc """
  Drives Caddy as the gateway's reverse proxy / load balancer.

  Replaces the former `Tunneld.Servers.Nginx`. Caddy is a single static
  binary configured entirely through its JSON admin API — there is no config
  template, no `sites-available` symlink dance, and no reload signal. Config
  changes are `PUT` against the admin endpoint and are atomic.

  ## Two planes (kept distinct)

  * **LAN** — one server listens on `0.0.0.0:18000` and routes by Host header
    (`<name>.tunneld.lan`). This is the subnet plane: dnsmasq resolves
    `*.tunneld.lan` to the gateway, Caddy fronts every resource.
  * **Loopback** — every resource also gets its own server bound to a unique
    `127.0.0.1:2xxxx` with **no host matcher**, pointing at the same backend
    pool. Tools like zrok / cloudflared / ngrok / manual `ssh -L` forwards do
    not send the `tunneld.lan` Host header, so they would hit the wrong
    backend or none; the loopback listener lets them target a fixed local
    port instead.

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
    %{
      "listen" => ["127.0.0.1:#{r["loopback_port"]}"],
      "routes" => [%{"handle" => [reverse_proxy(r["pool"])]}],
      "automatic_https" => %{"disable" => true}
    }
  end

  defp r_empty(nil), do: true
  defp r_empty(""), do: true
  defp r_empty(_), do: false

  # --- apply ---

  defp push_config(config) do
    body = Jason.encode!(config)

    # POST /load atomically replaces the entire config (the recommended way to
    # load a full new config). PUT /config/ would 409 when a config already
    # exists.
    case HTTPoison.post(
           @admin_url <> "load",
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

defmodule Tunneld.Publish do
  @moduledoc """
  Serve a gateway resource on a managed machine's public IP.

  A resource already resolves to `<name>.tunneld.lan:18000` on the gateway's
  Caddy. Publishing puts a second Caddy on a managed machine that listens on a
  public port and reverse-proxies **to the gateway's Caddy over the overlay**,
  rewriting the `Host` header so the gateway's existing route matches:

      internet -> <machine_public_ip>:<port> -> wg -> 10.88.0.1:18000 -> pool

  Proxying to `10.88.0.1:18000` rather than straight at the resource's LAN
  backends is the whole trick. Traffic **terminates on the gateway** (INPUT,
  where tcp/18000 is already allowed on every interface) and the gateway then
  opens its own connection to the backend (OUTPUT). It never crosses the
  gateway's FORWARD chain, which is `DROP` and only permits
  `RELATED,ESTABLISHED` back from the overlay. So publishing needs **no new
  gateway firewall rules and exposes no LAN device to the machine** - the older
  removed implementation pointed the remote Caddy at the pool directly and
  could never have connected.

  Config is written to a file and loaded by a systemd unit, not pushed through
  Caddy's admin API. The admin endpoint is disabled outright: a remote admin
  API is a remote-config-execution surface, and the previous attempt at this
  shipped a bug where the pushed config moved the admin listener and locked the
  gateway out of every later push.

  The one step this cannot do is the **provider firewall** (Vultr and friends).
  That is surfaced to the operator as an explicit instruction, and then
  `verify/1` checks the result from the gateway's own internet connection -
  the machine's public IP routes out the upstream NIC, not through the tunnel
  (`Table = off` means only /32s are installed), so that curl is a genuine
  round trip in from the outside.
  """

  require Logger

  alias Tunneld.Machines.SSH

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @config_path "/etc/tunneld-caddy.json"
  @unit_path "/etc/systemd/system/tunneld-caddy.service"
  @unit "tunneld-caddy"

  @doc "All publish records, keyed by resource id."
  def all do
    case Tunneld.Persistence.read_json(store_path()) do
      {:ok, %{"published" => map}} when is_map(map) -> map
      _ -> %{}
    end
  end

  @doc "The publish record for a resource, or nil."
  def get(resource_id), do: Map.get(all(), resource_id)

  @doc "Publish records for a machine."
  def for_machine(machine_id) do
    all() |> Enum.filter(fn {_id, p} -> p["machine_id"] == machine_id end) |> Map.new()
  end

  @doc """
  Publish a resource on a machine's public IP at `port`.

  Returns `{:ok, record}` or `{:error, reason}`. Idempotent: re-running
  re-installs Caddy, rewrites the config and re-opens the OS firewall, which is
  the supported repair path after the machine reboots.
  """
  def publish(resource, machine, port) when is_map(resource) and is_map(machine) do
    with {:ok, port} <- validate_port(port),
         :ok <- ensure_caddy(machine),
         record <- build_record(resource, machine, port),
         :ok <- put_record(resource["id"] || resource[:id], record),
         :ok <- sync_machine(machine),
         :ok <- open_os_firewall(machine, port) do
      {:ok, record}
    end
  end

  @doc "Stop serving a resource publicly. Idempotent."
  def unpublish(resource_id, machine) do
    record = get(resource_id)
    delete_record(resource_id)
    _ = if machine, do: sync_machine(machine), else: :ok

    if record && machine && record["port"] do
      _ = close_os_firewall(machine, record["port"])
    end

    :ok
  end

  @doc """
  Check the published URL from the gateway's own internet connection.

  Updates and returns the record with `status` of `"live"` or `"unreachable"`.
  """
  def verify(resource_id) do
    case get(resource_id) do
      nil ->
        {:error, :not_published}

      record ->
        status = if reachable?(record), do: "live", else: "unreachable"

        updated =
          record
          |> Map.put("status", status)
          |> Map.put("last_checked", DateTime.utc_now() |> DateTime.to_iso8601())

        put_record(resource_id, updated)
        {:ok, updated}
    end
  end

  @doc "The operator steps that tunneld cannot perform itself."
  def manual_steps(record) do
    [
      %{
        "title" => "1. Open the port in your provider firewall",
        "code" =>
          "Allow inbound TCP/#{record["port"]} to #{record["address"]} in the machine's " <>
            "cloud-provider firewall (e.g. a Vultr firewall group). This cannot be done over " <>
            "SSH - it is the same kind of step as UDP/51821 for WireGuard."
      },
      %{
        "title" => "2. Your service is now at",
        "code" => record["url"]
      },
      %{
        "title" => "3. To add a domain or TLS, do it yourself on the machine",
        "code" =>
          "Open Terminal on this machine from the dashboard, then edit " <>
            "#{@config_path} (or run your own Caddy/nginx alongside). Tunneld only " <>
            "manages the plain IP:port listener above."
      }
    ]
  end

  # --- internals ---

  defp build_record(resource, machine, port) do
    name = resource["name"] || resource[:name]

    %{
      "machine_id" => machine["id"],
      "machine_name" => machine["name"],
      "address" => machine["address"],
      "port" => port,
      "lan_host" => Tunneld.Caddy.lan_hostname(name),
      "url" => "http://#{machine["address"]}:#{port}",
      "status" => "pending",
      "last_checked" => nil
    }
  end

  defp validate_port(port) when is_binary(port) do
    case Integer.parse(String.trim(port)) do
      {n, ""} -> validate_port(n)
      _ -> {:error, :invalid_port}
    end
  end

  defp validate_port(port) when is_integer(port) and port > 0 and port < 65_536, do: {:ok, port}
  defp validate_port(_), do: {:error, :invalid_port}

  @doc """
  Build the machine's Caddy config: one server per published resource, each
  proxying to the gateway's Caddy with the resource's LAN host set.
  """
  def build_config(published) when is_map(published) do
    gw = "#{Tunneld.Overlay.gateway_overlay_ip()}:#{Tunneld.Caddy.public_port()}"

    servers =
      Map.new(published, fn {id, p} ->
        {"pub_#{id}",
         %{
           "listen" => [":#{p["port"]}"],
           "automatic_https" => %{"disable" => true},
           "routes" => [
             %{
               "handle" => [
                 %{
                   "handler" => "reverse_proxy",
                   "upstreams" => [%{"dial" => gw}],
                   "headers" => %{
                     "request" => %{"set" => %{"Host" => [p["lan_host"]]}}
                   }
                 }
               ]
             }
           ]
         }}
      end)

    %{
      "admin" => %{"disabled" => true},
      "apps" => %{"http" => %{"servers" => servers}}
    }
  end

  defp sync_machine(machine) do
    config = build_config(for_machine(machine["id"]))
    json = Jason.encode!(config, pretty: true)

    if @mock do
      dir = Path.join(Tunneld.Config.fs_root(), "publish")
      File.mkdir_p!(dir)
      File.write(Path.join(dir, "#{machine["id"]}.json"), json)
      :ok
    else
      with {:ok, _} <- write_remote(machine, @config_path, json),
           {:ok, _} <- SSH.run(machine, "systemctl restart #{@unit}") do
        :ok
      else
        {:error, reason} -> {:error, {:caddy_reload_failed, reason}}
      end
    end
  end

  defp ensure_caddy(machine) do
    if @mock, do: :ok, else: real_ensure_caddy(machine)
  end

  defp real_ensure_caddy(machine) do
    install = """
    if ! command -v caddy >/dev/null 2>&1 && [ ! -x /usr/local/bin/caddy ]; then
      ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
      curl -fsSL -o /usr/local/bin/caddy "https://caddyserver.com/api/download?os=linux&arch=$ARCH" || exit 1
      chmod +x /usr/local/bin/caddy
    fi
    command -v caddy >/dev/null 2>&1 || ln -sf /usr/local/bin/caddy /usr/bin/caddy
    """

    unit = """
    [Unit]
    Description=Tunneld public listener (Caddy)
    After=network-online.target

    [Service]
    ExecStart=/usr/local/bin/caddy run --config #{@config_path}
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    """

    with {:ok, _} <- SSH.run(machine, install),
         {:ok, _} <- write_remote(machine, @config_path, Jason.encode!(build_config(%{}))),
         {:ok, _} <- write_remote(machine, @unit_path, unit),
         {:ok, _} <- SSH.run(machine, "systemctl daemon-reload && systemctl enable #{@unit}") do
      :ok
    else
      {:error, reason} -> {:error, {:caddy_install_failed, reason}}
    end
  end

  defp open_os_firewall(machine, port) do
    unless @mock do
      SSH.run(
        machine,
        "ufw allow #{port}/tcp 2>/dev/null || " <>
          "iptables -I INPUT 1 -p tcp --dport #{port} -j ACCEPT 2>/dev/null || true"
      )
    end

    :ok
  end

  defp close_os_firewall(machine, port) do
    unless @mock do
      SSH.run(
        machine,
        "ufw delete allow #{port}/tcp 2>/dev/null || " <>
          "iptables -D INPUT -p tcp --dport #{port} -j ACCEPT 2>/dev/null || true"
      )
    end

    :ok
  end

  defp reachable?(record) do
    if @mock, do: true, else: real_reachable?(record)
  end

  defp real_reachable?(record) do
    cmd =
      "curl -s -o /dev/null -w '%{http_code}' --max-time 8 " <>
        "http://#{record["address"]}:#{record["port"]}/"

    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {code, 0} -> String.trim(code) not in ["", "000"]
      _ -> false
    end
  end

  defp write_remote(machine, path, content) do
    cmd =
      "mkdir -p #{Path.dirname(path)} && cat > #{path} <<'TUNNELD_EOF'\n#{content}\nTUNNELD_EOF"

    SSH.run(machine, cmd)
  end

  defp put_record(id, record) do
    Tunneld.Persistence.write_json(store_path(), %{"published" => Map.put(all(), id, record)})
    :ok
  end

  defp delete_record(id) do
    Tunneld.Persistence.write_json(store_path(), %{"published" => Map.delete(all(), id)})
    :ok
  end

  defp store_path, do: Path.join(Tunneld.Config.fs_root(), "publish.json")
end

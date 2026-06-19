defmodule Tunneld.Servers.Nginx do
  @moduledoc """
  Generates and manages per-resource nginx reverse proxy configurations.

  Each resource gets one nginx server block that:

  - Listens on `0.0.0.0:18000` so LAN devices can reach it via the
    local DNS name (`<name>.tunneld.lan`) resolved by dnsmasq to the gateway.
  - Matches `server_name` against the resource's local DNS name.
  - Proxies to an upstream block that load-balances the resource's backend
    pool (one or more `IP:port` entries).

  Config files follow the sites-available/sites-enabled symlink pattern.
  In mock mode, files are written under the local data directory instead of
  `/etc/nginx/`.

  This is a plain module (not a GenServer) - all functions are called
  synchronously by the Resources server.
  """

  require Logger

  @service_name "nginx"
  @public_port 18000
  @lan_domain "tunneld.lan"

  defp mock_mode?, do: Application.get_env(:tunneld, :mock_data, false) in [true, "true"]

  @doc "The LAN domain used for resource DNS names."
  def lan_domain, do: @lan_domain

  @doc "The port nginx listens on for resource traffic."
  def public_port, do: @public_port

  @doc """
  Build the local DNS hostname for a resource name (e.g. `"printer"` -> `"printer.tunneld.lan"`).
  """
  def lan_hostname(name) when is_binary(name) do
    "#{name}.#{@lan_domain}"
  end

  @doc """
  Create or update the nginx config for a resource.
  """
  def upsert_resource_config(%{"id" => id, "name" => name, "pool" => pool} = resource)
      when is_binary(id) and is_binary(name) and is_list(pool) do
    mock? = mock_mode?()
    available_path = available_path(id, mock?)
    enabled_path = enabled_path(id, mock?)

    with :ok <- ensure_dirs(mock?),
         :ok <- ensure_pool(pool),
         :ok <- File.write(available_path, render_config(resource)),
         :ok <- ensure_symlink(available_path, enabled_path),
         :ok <- reload_nginx(mock?) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to write nginx config for #{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def upsert_resource_config(_), do: {:error, :invalid_resource}

  @doc """
  Remove nginx config for a resource.
  """
  def remove_resource_config(id) when is_binary(id) do
    mock? = mock_mode?()
    available_path = available_path(id, mock?)
    enabled_path = enabled_path(id, mock?)

    _ = File.rm(enabled_path)
    _ = File.rm(available_path)

    reload_nginx(mock?)
  end

  def remove_resource_config(_), do: {:error, :invalid_resource}

  defp render_config(resource) do
    id = resource["id"]
    name = resource["name"]
    server_name = lan_hostname(name)

    upstream_name = "tunneld_#{id}_pool"
    pool = Map.get(resource, "pool", [])

    servers =
      pool
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map_join("\n", fn entry -> "    server #{entry};" end)

    """
    upstream #{upstream_name} {
    #{servers}
    }

    server {
        listen 0.0.0.0:#{@public_port};
        server_name #{server_name};

        location / {
            proxy_pass http://#{upstream_name};

            client_max_body_size 0;
            proxy_request_buffering off;

            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Port #{@public_port};
        }
    }
    """
  end

  defp ensure_dirs(mock?) do
    with :ok <- ensure_dir(base_dir(mock?)),
         :ok <- ensure_dir(Path.join(base_dir(mock?), "sites-available")),
         :ok <- ensure_dir(Path.join(base_dir(mock?), "sites-enabled")) do
      :ok
    end
  end

  defp ensure_symlink(source, destination) do
    case File.ln_s(source, destination) do
      :ok -> :ok
      {:error, :eexist} ->
        case File.read_link(destination) do
          {:ok, ^source} -> :ok
          {:ok, _other} ->
            _ = File.rm(destination)
            File.ln_s(source, destination)
          {:error, _} ->
            _ = File.rm(destination)
            File.ln_s(source, destination)
        end
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Reload nginx configuration. No-op in mock mode."
  def reload, do: reload_nginx(mock_mode?())

  defp reload_nginx(true), do: :ok
  defp reload_nginx(false) do
    case System.cmd("systemctl", ["reload", @service_name]) do
      {_, 0} -> :ok
      err -> {:error, err}
    end
  end

  defp available_path(id, mock?) do
    Path.join([available_dir(mock?), "tunneld_#{id}"])
  end

  defp enabled_path(id, mock?) do
    Path.join([enabled_dir(mock?), "tunneld_#{id}"])
  end

  defp available_dir(mock?), do: Path.join(base_dir(mock?), "sites-available")
  defp enabled_dir(mock?), do: Path.join(base_dir(mock?), "sites-enabled")

  defp base_dir(true), do: Path.join([fs_root(), "nginx"])
  defp base_dir(false), do: "/etc/nginx"

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      {:error, r} -> {:error, r}
    end
  end

  defp fs_root(), do: Tunneld.Config.fs_root()

  defp ensure_pool(pool) when is_list(pool) and length(pool) > 0, do: :ok
  defp ensure_pool(_), do: {:error, :invalid_pool}
end
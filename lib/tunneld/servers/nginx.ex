defmodule Tunneld.Servers.Nginx do
  @moduledoc false
  require Logger
  @service_name "nginx"
  @public_port 18000
  @private_port_base 20000
  @private_port_range 10000

  @doc """
  Create or update the nginx config for a resource (shared for public/private).
  """
  def upsert_resource_config(%{"id" => id, "pool" => pool} = resource) when is_list(pool) do
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

  @doc """
  Calculate a deterministic private port based on the Identifier (Name or ID).
  """
  def get_private_port(identifier) when is_binary(identifier) do
    offset = :erlang.phash2(identifier, @private_port_range)
    @private_port_base + offset
  end

  defp render_config(resource) do
    id = resource["id"]
    listen_ip = Map.get(resource, "ip", "127.0.0.1")

    # Determine names first
    reserved = get_in(resource, ["tunneld", "reserved"]) || %{}
    public_name = Map.get(reserved, "public", "#{id}-public")
    private_name = Map.get(reserved, "private", "#{id}-private")

    public_port = @public_port
    private_port = get_private_port(private_name)

    upstream_name = "tunneld_#{id}_pool"
    pool = Map.get(resource, "pool", [])

    # Retrieve root domain from config if available (e.g. "example.com")
    root_domain = Application.get_env(:tunneld, :root_domain)

    # Logic to determine the Host header for private access:
    spoofed_host =
      cond do
        String.contains?(public_name, ".") ->
          public_name

        is_binary(root_domain) and root_domain != "" ->
          public_name <> "." <> String.trim_leading(root_domain, ".")

        true ->
          public_name
      end

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
        listen #{listen_ip}:#{public_port};
        server_name #{public_name} ~^#{public_name}\..+$;

        location / {
            proxy_pass http://#{upstream_name};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    server {
        listen #{listen_ip}:#{private_port};
        server_name _ #{private_name};

        location / {
            proxy_pass http://#{upstream_name};
            proxy_set_header Host #{spoofed_host};
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
    """
  end

  # ... (The rest of your helper functions ensure_dirs, etc. remain unchanged) ...
  defp ensure_dirs(mock?) do
    with :ok <- ensure_dir(base_dir(mock?)),
         :ok <- ensure_dir(Path.join(base_dir(mock?), "sites-available")),
         :ok <- ensure_dir(Path.join(base_dir(mock?), "sites-enabled")) do
      :ok
    end
  end

  defp ensure_symlink(source, destination) do
    case File.ln_s(source, destination) do
      :ok ->
        :ok

      {:error, :eexist} ->
        case File.read_link(destination) do
          {:ok, ^source} ->
            :ok

          {:ok, _other} ->
            _ = File.rm(destination)
            File.ln_s(source, destination)

          {:error, _} ->
            _ = File.rm(destination)
            File.ln_s(source, destination)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

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

  defp fs_root() do
    case Application.get_env(:tunneld, :fs) do
      nil -> "/var/lib/tunneld"
      kw when is_list(kw) -> Keyword.get(kw, :root, "/var/lib/tunneld")
      map when is_map(map) -> Map.get(map, :root) || Map.get(map, "root") || "/var/lib/tunneld"
      bin when is_binary(bin) -> bin
    end
  end

  defp ensure_pool(pool) when is_list(pool) and length(pool) > 0, do: :ok
  defp ensure_pool(_), do: {:error, :invalid_pool}

  defp mock_mode?() do
    Application.get_env(:tunneld, :mock_data) in [true, "true"]
  end
end

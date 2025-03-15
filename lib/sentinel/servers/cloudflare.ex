defmodule Sentinel.Servers.Cloudflare do
  @moduledoc """
  Cloudflared server that manages tunnels and services.

  Features:
  - Manage Cloudflare tunnels via `cloudflared` CLI.
  - Add, remove, and persist ingress services.
  - Retrieve tunnel and config details.
  - Check service health via HTTP requests.
  """

  use GenServer
  require Logger

  @default_tunnel_name "sentinel-tunnel"

  # Public API: Start the GenServer
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("Initializing Cloudflared tunnel manager...")
    state = load_state()

    {:ok, state}
  end

  # -----------------------------
  # INTERNAL SERVER CALLBACKS
  # -----------------------------

  @impl true
  def handle_call(:get_tunnel_id, _from, state) do
    {:reply, state.tunnel_id, state}
  end

  @impl true
  def handle_call(:get_config_json, _from, state) do
    case File.read(state.config_path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, parsed} -> {:reply, Jason.encode!(parsed), state}
          {:error, _} -> {:reply, Jason.encode!(%{}), state}
        end

      {:error, _} ->
        {:reply, Jason.encode!(%{}), state}
    end
  end

  @impl true
  def handle_call(:list_services, _from, state) do
    {:reply, Map.keys(state.services), state}
  end

  @impl true
  def handle_call(:delete_tunnel, _from, state) do
    Logger.info("Deleting tunnel and cleaning up config...")

    System.cmd("cloudflared", ["tunnel", "delete", state.tunnel_name])
    File.rm(state.config_path)

    {:reply, :ok, %{state | tunnel_id: nil, services: %{}}}
  end

  @impl true
  def handle_cast({:create_tunnel, name}, state) do
    if state.tunnel_id do
      Logger.warn("A tunnel already exists: #{state.tunnel_id}. Not creating a new one.")
      {:noreply, state}
    else
      Logger.info("Creating tunnel: #{name}")

      {output, _exit_code} = System.cmd("cloudflared", ["tunnel", "create", name])

      case Regex.run(~r/Created tunnel .* with id (\S+)/, output) do
        [_, tunnel_id] ->
          Logger.info("Tunnel ID: #{tunnel_id}")
          update_config(%{"tunnel" => name, "ingress" => []})

          new_state = %{state | tunnel_id: tunnel_id, tunnel_name: name, services: %{}}
          {:noreply, new_state}

        _ ->
          Logger.error("Failed to extract tunnel ID.")
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_cast({:add_service, name, address}, state) do
    Logger.info("Adding service: #{name} -> #{address}")

    parsed = read_config()
    ingress = parsed["ingress"] ++ [%{"hostname" => name, "service" => "http://#{address}"}]

    update_config(Map.put(parsed, "ingress", ingress))

    updated_services = Map.put(state.services, name, %{address: address, status: :unknown})
    {:noreply, %{state | services: updated_services}}
  end

  @impl true
  def handle_cast({:remove_service, name}, state) do
    Logger.info("Removing service: #{name}")

    parsed = read_config()
    ingress = Enum.reject(parsed["ingress"], fn s -> s["hostname"] == name end)

    update_config(Map.put(parsed, "ingress", ingress))

    updated_services = Map.delete(state.services, name)
    {:noreply, %{state | services: updated_services}}
  end

  @impl true
  def handle_cast(:ping_services, state) do
    Logger.info("Checking service health...")

    updated_services =
      Enum.map(state.services, fn {name, service} ->
        is_up = ping_service(service.address)
        {name, %{service | status: if(is_up, do: :up, else: :down)}}
      end)
      |> Enum.into(%{})

    {:noreply, %{state | services: updated_services}}
  end

  @impl true
  def handle_cast(:restart_tunnel, state) do
    Logger.info("Restarting Cloudflared service with config: #{state.config_path}")

    System.cmd("cloudflared", ["tunnel", "--config", state.config_path, "run"])
    Process.sleep(2000)  # Allow time to restart

    {:noreply, state}
  end

  # -----------------------------
  # TUNNEL MANAGEMENT
  # -----------------------------

  @doc "Creates a new Cloudflared tunnel."
  def create_tunnel(name) do
    GenServer.cast(__MODULE__, {:create_tunnel, name})
  end

  @doc "Returns the current tunnel ID."
  def get_tunnel_id() do
    GenServer.call(__MODULE__, :get_tunnel_id)
  end

  @doc "Deletes the existing tunnel and all DNS records."
  def delete_tunnel() do
    GenServer.call(__MODULE__, :delete_tunnel)
  end

  # -----------------------------
  # SERVICE MANAGEMENT
  # -----------------------------

  @doc "Adds a new service to the tunnel."
  def add_service(name, address) do
    GenServer.cast(__MODULE__, {:add_service, name, address})
  end

  @doc "Removes a service from the tunnel."
  def remove_service(name) do
    GenServer.cast(__MODULE__, {:remove_service, name})
  end

  @doc "Lists all configured services."
  def list_services() do
    GenServer.call(__MODULE__, :list_services)
  end

  # -----------------------------
  # SERVICE HEALTH CHECKING
  # -----------------------------

  @doc "Pings all configured services to check if they are up or down."
  def ping_services() do
    GenServer.cast(__MODULE__, :ping_services)
  end

  @impl true
  @doc "Restarts Cloudflared service with the correct config file."
  def restart_tunnel() do
    GenServer.cast(__MODULE__, :restart_tunnel)
  end

  # -----------------------------
  # HELPER FUNCTIONS
  # -----------------------------

  defp load_state() do
    if File.exists?(path()) do
      parsed = read_config()

      tunnel_id =
        case parsed do
          %{"tunnel" => _name} ->
            # Get the tunnel ID from the credentials file if it exists
            extract_tunnel_id_from_file()

          _ ->
            nil
        end

      Logger.info("Loaded tunnel ID: #{tunnel_id || "None"}")

      %{
        tunnel_id: tunnel_id,
        tunnel_name: @default_tunnel_name,
        config_path: path(),
        services: load_services(path())
      }
    else
      Logger.warn("Config file not found. No tunnel loaded.")
      %{
        tunnel_id: nil,
        tunnel_name: @default_tunnel_name,
        config_path: path(),
        services: %{}
      }
    end
  end

  defp read_config do
    case File.read(path()) do
      {:ok, content} -> YamlElixir.read_from_string(content) |> elem(1)
      _ -> %{"ingress" => []}
    end
  end

  defp update_config(new_config) do
    yaml_content = map_to_yaml(new_config)
    File.write!(path(), yaml_content)
  end

  defp ping_service(address) do
    {_, code} = System.cmd("curl", ["-s", "-o", "/dev/null", "-w", "%{http_code}", address])
    code == "200"
  end

  defp load_services(path) do
    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, parsed} -> extract_services(parsed)
          {:error, _} -> %{}
        end

      {:error, _} ->
        %{}
    end
  end

  # Extracts the service details from the YAML structure
  defp extract_services(parsed) do
    ingress = Map.get(parsed, "ingress", [])

    Enum.reduce(ingress, %{}, fn entry, acc ->
      if Map.has_key?(entry, "hostname") and Map.has_key?(entry, "service") do
        Map.put(acc, entry["hostname"], %{
          address: entry["service"],
          # Default status until we ping it
          status: :unknown
        })
      else
        acc
      end
    end)
  end

  defp map_to_yaml(%{"tunnel" => tunnel, "ingress" => ingress}) do
    """
    tunnel: #{tunnel}
    ingress:
    #{Enum.map_join(ingress, "\n", &format_ingress_entry/1)}
    """
  end

  defp format_ingress_entry(%{"hostname" => hostname, "service" => service}) do
    "  - hostname: #{hostname}\n    service: #{service}"
  end

  defp format_ingress_entry(%{"service" => service}) do
    "  - service: #{service}"
  end

  defp extract_tunnel_id_from_file() do
    case File.read(path()) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, %{"tunnel" => tunnel_id}} ->
            Logger.info("Loaded tunnel ID from /data/: #{tunnel_id}")
            tunnel_id

          _ ->
            Logger.warn("No tunnel ID found in /data/cloudflare_conf.yml.")
            nil
        end

      {:error, reason} ->
        Logger.error("Failed to read Cloudflared config: #{inspect(reason)}")
        nil
    end
  end


  # Path helper
  defp path(), do: "./" <> config_fs(:root) <> config_fs(:cloudflared)

  # Config helper
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end

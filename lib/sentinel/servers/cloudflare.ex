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

    # Ensure config exists and load state
    ensure_config_exists(path())
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
      {:error, _} -> {:reply, Jason.encode!(%{}), state}
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
    Logger.info("Creating tunnel: #{name}")

    # Delete existing tunnel if it exists
    if state.tunnel_id do
      System.cmd("cloudflared", ["tunnel", "delete", state.tunnel_name])
    end

    {_, id} = System.cmd("cloudflared", ["tunnel", "create", name])
    new_id = String.trim(id)

    update_config(%{"tunnel" => name, "ingress" => []})

    new_state = %{state | tunnel_id: new_id, tunnel_name: name, services: %{}}
    {:noreply, new_state}
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
        {name, %{service | status: (if is_up, do: :up, else: :down)}}
      end)
      |> Enum.into(%{})

    {:noreply, %{state | services: updated_services}}
  end

  @impl true
  def handle_cast(:restart_tunnel, state) do
    Logger.info("Restarting Cloudflared service...")
    System.cmd("systemctl", ["restart", "cloudflared"])
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

  @doc "Manually restarts the Cloudflared tunnel service."
  def restart_tunnel() do
    GenServer.cast(__MODULE__, :restart_tunnel)
  end

  # -----------------------------
  # HELPER FUNCTIONS
  # -----------------------------

  defp load_state() do
    tunnel_id = System.get_env("CLOUDFLARED_TUNNEL_ID") || nil
    services = load_services(path())

    %{
      tunnel_id: tunnel_id,
      tunnel_name: @default_tunnel_name,
      config_path: path(),
      services: services
    }
  end

  defp ensure_config_exists(path) do
    unless File.exists?(path) do
      Logger.info("Creating empty config.yml")
      File.write(path, "tunnel: #{@default_tunnel_name}\ningress: []\n")
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
      {:error, _} -> %{}
    end
  end

  # Extracts the service details from the YAML structure
  defp extract_services(parsed) do
    ingress = Map.get(parsed, "ingress", [])

    Enum.reduce(ingress, %{}, fn entry, acc ->
      if Map.has_key?(entry, "hostname") and Map.has_key?(entry, "service") do
        Map.put(acc, entry["hostname"], %{
          address: entry["service"],
          status: :unknown  # Default status until we ping it
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

  # Path helper
  defp path(), do: "./" <> config_fs(:root) <> config_fs(:cloudflared)

  # Config helper
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end

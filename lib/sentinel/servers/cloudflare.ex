defmodule Sentinel.Servers.Cloudflare do
  @moduledoc """
  Manages Cloudflare tunnel services.

  Features:
  - Uses an existing Cloudflare tunnel.
  - Manages ingress rules (adding/removing services).
  - Ensures a valid configuration exists on startup.
  - Restarts Cloudflared when the config is updated.
  """

  use GenServer
  require Logger

  @default_tunnel_name "sentinel-local"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("Initializing Cloudflared tunnel manager...")

    # Ensure config exists before loading state
    ensure_config_exists()

    # Start a background process to check for a valid tunnel ID
    Process.send_after(self(), :fetch_tunnel_id, 5000)

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
  def handle_call(:list_services, _from, state) do
    {:reply, Map.keys(state.services), state}
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
  def handle_cast({:add_service, name, address}, state) do
    Logger.info("Adding service: #{name} -> #{address}")

    # Ensure Cloudflare knows about the hostname
    System.cmd("cloudflared", ["tunnel", "route", "dns", @default_tunnel_name, name])

    parsed = read_config()

    ingress =
      Map.get(parsed, "ingress", []) ++ [%{"hostname" => name, "service" => "http://#{address}"}]

    update_config(Map.put(parsed, "ingress", ingress))

    updated_services = Map.put(state.services, name, %{address: address, status: :unknown})
    {:noreply, %{state | services: updated_services}}
  end

  @impl true
def handle_cast({:remove_service, name}, state) do
  Logger.info("Removing service: #{name}")

  # Remove the CNAME record from Cloudflare
  {output, exit_code} = System.cmd("cloudflared", ["tunnel", "route", "dns", "--delete", @default_tunnel_name, name])

  if exit_code != 0 do
    Logger.error("Failed to remove subdomain #{name}. Cloudflared output: #{output}")
  else
    Logger.info("Successfully removed subdomain #{name} from Cloudflare.")
  end

  # Remove from config
  parsed = read_config()
  ingress = Enum.reject(parsed["ingress"], fn s -> s["hostname"] == name end)

  update_config(Map.put(parsed, "ingress", ingress))

  updated_services = Map.delete(state.services, name)
  {:noreply, %{state | services: updated_services}}
end

  @impl true
  def handle_cast(:restart_tunnel, state) do
    Logger.info("Restarting Cloudflared service with config: #{state.config_path}")

    System.cmd("cloudflared", ["tunnel", "--config", state.config_path, "run"])
    # Allow time to restart
    Process.sleep(5000)

    {:noreply, state}
  end

  # -----------------------------
  # Messages
  # -----------------------------
  @impl true
  def handle_info(:fetch_tunnel_id, state) do
    case get_existing_tunnel_id() do
      nil ->
        Logger.warn("Tunnel ID still missing, retrying in 5s...")
        Process.send_after(self(), :fetch_tunnel_id, 5000)
        {:noreply, state}

      tunnel_id when tunnel_id != state.tunnel_id ->
        Logger.info("Updating tunnel ID to #{tunnel_id}")

        # Read existing config and update only the tunnel ID
        parsed = read_config()
        updated_config = Map.put(parsed, "tunnel", tunnel_id)
        update_config(updated_config)

        # Update state and stop retrying
        {:noreply, %{state | tunnel_id: tunnel_id}}

      _ ->
        {:noreply, state}
    end
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

  @doc "Restarts Cloudflared service."
  def restart_tunnel() do
    GenServer.cast(__MODULE__, :restart_tunnel)
  end

  # -----------------------------
  # HELPER FUNCTIONS
  # -----------------------------

  def ensure_config_exists() do
    unless File.exists?(path()) do
      Logger.warn("Cloudflare config not found. Initializing with placeholder.")

      default_config = %{
        "tunnel" => "unknown",
        "ingress" => [%{"service" => "http_status:404"}]
      }

      update_config(default_config)
    end
  end

  defp load_state() do
    parsed = read_config()

    tunnel_id =
      case parsed do
        %{"tunnel" => id} -> id
        _ -> "unknown"
      end

    Logger.info("Loaded tunnel ID: #{tunnel_id}")

    %{
      tunnel_id: tunnel_id,
      tunnel_name: @default_tunnel_name,
      config_path: path(),
      services: load_services(parsed)
    }
  end

  def read_config do
    case File.read(path()) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, parsed} -> Map.update(parsed, "ingress", [], fn v -> v || [] end)
          _ -> %{"ingress" => []}
        end

      _ ->
        %{"ingress" => []}
    end
  end

  defp update_config(new_config) do
    ingress = Map.get(new_config, "ingress", [])

    final_ingress =
      case List.last(ingress) do
        %{"service" => _} -> ingress
        _ -> ingress ++ [%{"service" => "http_status:404"}]
      end

    updated_config = Map.put(new_config, "ingress", final_ingress)
    yaml_content = map_to_yaml(updated_config)
    File.write!(path(), yaml_content)
  end

  defp load_services(parsed) do
    ingress = Map.get(parsed, "ingress", [])

    if is_list(ingress) do
      Enum.reduce(ingress, %{}, fn entry, acc ->
        if Map.has_key?(entry, "hostname") and Map.has_key?(entry, "service") do
          Map.put(acc, entry["hostname"], %{address: entry["service"], status: :unknown})
        else
          acc
        end
      end)
    else
      %{}
    end
  end

  def get_existing_tunnel_id() do
    {output, _} = System.cmd("cloudflared", ["tunnel", "list"])

    case Regex.run(~r/^([a-f0-9\-]+)\s+sentinel-local/m, output) do
      [_, tunnel_id] -> tunnel_id
      _ -> nil
    end
  end

  defp map_to_yaml(%{"tunnel" => tunnel, "ingress" => ingress}) do
    """
    tunnel: #{tunnel}
    ingress:
    #{Enum.map_join(ingress, "\n", &format_ingress_entry/1)}
    """
    |> String.trim()
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

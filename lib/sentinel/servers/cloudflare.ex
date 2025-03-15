defmodule Sentinel.Servers.Cloudflare do
  @moduledoc """
  Extended GenServer-based Cloudflare tunnel manager.

  Features:
    • Creates a dedicated tunnel for each subdomain.
    • Provides functions to create, route, run, and delete tunnels.

  We use:
    1) cloudflared tunnel create <TUNNEL_NAME>
    2) cloudflared tunnel route dns <TUNNEL_NAME> <SUBDOMAIN>
    3) cloudflared tunnel run --url <LOCAL_SERVER> <TUNNEL_NAME>

  Also includes:
    • cloudflared tunnel cleanup <TUNNEL_NAME> before deletion to remove stale connections.
  """

  use GenServer
  require Logger

  @doc """
  Starts the GenServer under a supervisor.
  On init, we ensure the data file exists, read it,
  and restore any tunnels.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  @doc """
  Creates a brand-new tunnel for `subdomain`, sets up DNS route,
  and runs it with the local server (ip:port) you provide.
  Persists the new tunnel in the file so it auto-restores next time.

  Example usage:
      add_host("127.0.0.1:4000", "myapp.example.com")
  """
  def add_host(local_server, subdomain) do
    GenServer.cast(__MODULE__, {:add_host, local_server, subdomain})
  end

  @doc """
  Deletes the tunnel for `subdomain`, removing it from Cloudflare,
  killing the local process, and removing from the file.

  Also calls 'cloudflared tunnel cleanup' first to remove stale connections.
  """
  def remove_host(subdomain) do
    GenServer.cast(__MODULE__, {:remove_host, subdomain})
  end

  @doc """
  Lists all known subdomains currently tracked in the file.
  """
  def list_hosts do
    GenServer.call(__MODULE__, :list_hosts)
  end

  # ----------------------------------------------------------------
  #  GenServer callbacks
  # ----------------------------------------------------------------

  @impl true
  def init(_opts) do
    Logger.info("Starting Cloudflare Tunnel GenServer...")

    create_file_if_missing()

    case read_file() do
      {:ok, tunnels} ->
        Logger.info("Loaded tunnel data from file: #{inspect(tunnels)}")

        state = %{
          running_tunnels: %{},
          records: tunnels
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to load existing tunnel data: #{reason}")
        state = %{running_tunnels: %{}, records: []}
        {:ok, state}
    end
  end

  @impl true
  def handle_cast({:add_host, local_server, subdomain}, state) do
    # If subdomain already exists, skip
    if Enum.any?(state.records, &(&1["subdomain"] == subdomain)) do
      Logger.warn("Subdomain #{subdomain} is already known; skipping new tunnel.")
      {:noreply, state}
    else
      # Create a unique tunnel name from the subdomain
      tunnel_name = tunnel_name_for(subdomain)

      # 1) create the tunnel if missing
      unless tunnel_exists?(tunnel_name) do
        do_create_tunnel(tunnel_name)
      end

      # 2) add DNS route
      do_add_dns_route(tunnel_name, subdomain)

      # 3) run tunnel with local_server as the actual address
      port = do_run_tunnel(tunnel_name, local_server)

      # 4) store record in file + memory
      record = %{
        "subdomain" => subdomain,
        "tunnel_name" => tunnel_name,
        "local_server" => local_server
      }

      new_records = [record | state.records]
      new_running = Map.put(state.running_tunnels, subdomain, port)
      new_state = %{state | running_tunnels: new_running, records: new_records}

      write_file(new_records)
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:remove_host, subdomain}, state) do
    case Enum.find(state.records, &(&1["subdomain"] == subdomain)) do
      nil ->
        Logger.warn("No record found for subdomain=#{subdomain}")
        {:noreply, state}

      record ->
        tunnel_name = record["tunnel_name"]

        # 1) stop local process if running
        new_state = stop_local_tunnel(subdomain, state)

        # 2) cleanup + delete the tunnel in Cloudflare
        do_cleanup_tunnel(tunnel_name)
        do_delete_tunnel(tunnel_name)

        # 3) remove from file
        pruned_records = Enum.reject(new_state.records, &(&1["subdomain"] == subdomain))
        final_state = %{new_state | records: pruned_records}
        write_file(pruned_records)

        {:noreply, final_state}
    end
  end

  def handle_call(:list_hosts, _from, state) do
    # Return the subdomains from the records
    subs = Enum.map(state.records, & &1["subdomain"])
    {:reply, subs, state}
  end

  # ----------------------------------------------------------------Gen
  # Internal logic
  # ----------------------------------------------------------------

  defp stop_local_tunnel(subdomain, state) do
    case Map.fetch(state.running_tunnels, subdomain) do
      :error ->
        Logger.warn("No running tunnel for subdomain=#{subdomain}")
        state

      {:ok, port} ->
        Logger.info("Stopping local tunnel for subdomain=#{subdomain}")
        Port.close(port)
        new_map = Map.delete(state.running_tunnels, subdomain)
        %{state | running_tunnels: new_map}
    end
  end

  # ----------------------------------------------------------------
  # Cloudflared Commands
  # ----------------------------------------------------------------

  defp do_create_tunnel(tunnel_name) do
    Logger.info("Creating tunnel: #{tunnel_name}")
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "create", tunnel_name], stderr_to_stdout: true)

    if exit_code != 0 do
      Logger.error("Failed to create tunnel:\n#{output}")
    else
      Logger.info("Tunnel `#{tunnel_name}` created successfully.")
    end
  end

  defp do_add_dns_route(tunnel_name, subdomain) do
    Logger.info("Adding DNS route: #{subdomain} -> #{tunnel_name}")
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "route", "dns", tunnel_name, subdomain],
        stderr_to_stdout: true
      )

    if exit_code != 0 do
      Logger.error("Failed to add DNS route:\n#{output}")
    else
      Logger.info("DNS route for #{subdomain} added successfully.")
    end
  end

  defp do_run_tunnel(tunnel_name, local_server) do
    Logger.info("Running tunnel: #{tunnel_name} with --url #{local_server}...")
    Port.open({:spawn_executable, System.find_executable("cloudflared")}, [
      :binary,
      :exit_status,
      :hide,
      :use_stdio,
      args: [
        "tunnel", "run",
        "--loglevel", "fatal", # will make the logs less "chatty"
        "--url", local_server, tunnel_name]
    ])
  end

  defp do_cleanup_tunnel(tunnel_name) do
    Logger.info("Cleaning up stale connections for tunnel: #{tunnel_name}")
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "cleanup", tunnel_name], stderr_to_stdout: true)

    if exit_code != 0 do
      Logger.warn("Tunnel cleanup error (possibly no stale connections):\n#{output}")
    else
      Logger.info("Tunnel `#{tunnel_name}` cleaned up (stale connections removed).")
    end
  end

  defp do_delete_tunnel(tunnel_name) do
    Logger.info("Deleting tunnel: #{tunnel_name}")
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "delete", tunnel_name], stderr_to_stdout: true)

    if exit_code != 0 do
      Logger.error("Failed to delete tunnel:\n#{output}")
    else
      Logger.info("Tunnel `#{tunnel_name}` deleted successfully.")
    end
  end

  # ----------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------

  # e.g. subdomain="myapp.example.com" => "sentinel-myapp-example-com"
  defp tunnel_name_for(subdomain),
    do: "sentinel-" <> String.replace(subdomain, ".", "-")

  defp tunnel_exists?(tunnel_name) do
    {output, _exit_code} = System.cmd("cloudflared", ["tunnel", "list"], stderr_to_stdout: true)
    String.contains?(output, tunnel_name)
  end

  # ----------------------------------------------------------------
  # File-based persistence (borrowed from your Auth approach)
  # ----------------------------------------------------------------

  defp create_file_if_missing do
    unless file_exists?() do
      # Create a new file with empty array
      case File.write(path(), "[]") do
        :ok ->
          Logger.info("Created tunnel data file.")
        {:error, reason} ->
          Logger.error("Failed to create tunnel data file: #{inspect(reason)}")
      end
    end
  end

  defp read_file do
    case File.read(path()) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, decoded} ->
            {:ok, decoded} # expecting a list of records
          {:error, err} ->
            {:error, "Failed to decode file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  defp write_file(records) when is_list(records) do
    json = Jason.encode!(records)
    case File.write(path(), json) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("Failed to write to data file: #{inspect(reason)}")
    end
  end

  defp file_exists? do
    File.exists?(path())
  end

  defp path do
    "./" <> config_fs(:root) <> config_fs(:tunnels)
  end

  # For example, config :sentinel, :fs => %{ root: "some_dir/", tunnels: "cloudflare_tunnels.json" }
  defp config_fs do
    Application.get_env(:sentinel, :fs)
  end

  defp config_fs(key), do: config_fs()[key]
end

defmodule Sentinel.Servers.Cloudflare do
  @moduledoc """
  Extended GenServer-based Cloudflare tunnel manager.

  Features:
    • Creates a dedicated tunnel for each subdomain.
    • Provides functions to create, route, run, and delete tunnels.

  We use:
    1) cloudflared tunnel create <TUNNEL_NAME>
    2) cloudflared tunnel route dns <TUNNEL_NAME> <SUBDOMAIN>
    3) cloudflared tunnel run --url <LOCAL_SERVER> <TUNNEL_NAME> (in background)

  Also includes:
    • cloudflared tunnel cleanup <TUNNEL_NAME> before deletion to remove stale connections.

  Since we launch `cloudflared` in the background via `nohup`, it keeps running
  even if our Elixir app stops. We only store metadata about subdomains in a file
  so we can remove them later if desired.
  """

  use GenServer
  require Logger

  @max_retries 10
  @retry_delay 5_000

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  @doc """
  Starts the GenServer under a supervisor.
  On init, we ensure the data file exists and read it.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Lists all known subdomains currently tracked in the file.
  """
  def list_hosts do
    GenServer.call(__MODULE__, :list_hosts)
  end

  # ----------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------

  @impl true
  def init(_opts) do
    Logger.info("Starting Cloudflare Tunnel GenServer...")

    create_file_if_missing()

    case read_file() do
      {:ok, tunnels} ->
        Logger.info("Loaded tunnel data from file: #{inspect(tunnels)}")

        Enum.each(tunnels, fn data ->
          %{
            "tunnel_name" => tunnel_name,
            "subdomain" => _,
            "local_server" => local_server
          } = data

          retry_until_tunnel_exists(tunnel_name, fn ->
            do_run_tunnel_in_background(tunnel_name, local_server)
          end)
        end)

        {:ok, %{records: tunnels}}

      {:error, reason} ->
        Logger.error("Failed to load existing tunnel data: #{reason}")
        {:ok, %{records: []}}
    end
  end

  @impl true
  def handle_cast({:add_host, local_server, subdomain}, state) do
    # If subdomain already exists, skip
    if Enum.any?(state.records, &(&1["subdomain"] == subdomain)) do
      Logger.warn("Subdomain #{subdomain} is already known; skipping new tunnel.")

      # Broadcast that we connected the tunnel - error
      Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
        type: :error,
        message: "Unable to connect tunnel to server: #{subdomain}"
      })

      {:noreply, state}
    else
      tunnel_name = tunnel_name_for(subdomain)

      # 1) create the tunnel if missing
      unless tunnel_exists?(tunnel_name) do
        do_create_tunnel(tunnel_name)

        # Step Notification
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :info,
          message: "#{subdomain}: Tunnel Created"
        })
      end

      # 2) add DNS route
      do_add_dns_route(tunnel_name, subdomain)

      # 3) run tunnel in the background (nohup)
      do_run_tunnel_in_background(tunnel_name, local_server)

      # 4) store record in file + memory
      record = %{
        "subdomain" => subdomain,
        "tunnel_name" => tunnel_name,
        "local_server" => local_server
      }

      new_records = [record | state.records]
      new_state = %{state | records: new_records}

      write_file(new_records)

      # Broadcast that we disconnected the tunnel
      Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
        type: :info,
        message: "#{subdomain}: Tunnel successfully created"
      })

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:remove_host, subdomain}, state) do
    case Enum.find(state.records, &(&1["subdomain"] == subdomain)) do
      nil ->
        Logger.warn("No record found for subdomain=#{subdomain}")

        # Broadcast that we disconnected the tunnel - eeror
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :error,
          message: "No record found for subdomain: #{subdomain}"
        })

        {:noreply, state}

      record ->
        tunnel_name = record["tunnel_name"]
        do_cleanup_tunnel(tunnel_name)
        do_delete_tunnel(tunnel_name)

        # Make sure to remove DNS record from remote
        %{ success: success, data: data} = get_dns_record_details(subdomain)

        # We remove the Record by ID
        if success do
          remove_dns_record(data)
        end

        # Remove from file
        pruned_records = Enum.reject(state.records, &(&1["subdomain"] == subdomain))
        final_state = %{state | records: pruned_records}
        write_file(pruned_records)

        # Broadcast that we disconnected the tunnel
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :info,
          message: "Tunnel successfully disconnected for: #{subdomain}"
        })

        {:noreply, final_state}
    end
  end

  def handle_call(:list_hosts, _from, state) do
    subs = Enum.map(state.records, & &1["subdomain"])
    {:reply, subs, state}
  end

  # Get data around the persisted tunnel file - what we expect to have running
  def handle_call({:get_tunnel_data, ip, port}, _from, state) do
    {_, resp} = read_file()

    structured_data =
      Enum.reduce(resp, %{}, fn item, acc -> Map.put(acc, item["local_server"], item) end)

    {:reply, Map.get(structured_data, "#{ip}:#{port}", %{}), state}
  end

  # We no longer have any Port messages to handle (since we used nohup).
  # So no handle_info clauses needed for port data/exit_status.

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

      # Step Notification
      Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
        type: :error,
        message: "#{subdomain}: There was an error adding DNS route"
      })
    else
      Logger.info("DNS route for #{subdomain} added successfully.")

      # Step Notification
      Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
        type: :info,
        message: "#{subdomain}: DNS route added successfully"
      })
    end
  end

  # Instead of opening a Port, we spawn cloudflared via `nohup &`
  # so it runs detached from Elixir.
  defp do_run_tunnel_in_background(tunnel_name, local_server) do
    Logger.info("Launching cloudflared in background: #{tunnel_name} => #{local_server}")

    {output, _} =
      System.cmd("pgrep", ["-f", "cloudflared tunnel run --url #{local_server} #{tunnel_name}"])

    if String.trim(output) != "" do
      Logger.info("Tunnel #{tunnel_name} already running.")
      :ok
    else
      cmd = """
      nohup cloudflared tunnel run --url #{local_server} #{tunnel_name} \
      > /dev/null 2>&1 &
      """

      {output, exit_code} = System.cmd("sh", ["-c", cmd], stderr_to_stdout: true)

      if exit_code != 0 do
        Logger.error("Failed to spawn background cloudflared:\n#{inspect(output)}")
      else
        Logger.info("cloudflared was launched in background (exit_code=#{exit_code}).")
      end
    end
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
    Logger.info("Stopping tunnel: #{tunnel_name}")

    # Check if process exists before killing
    {output, _} = System.cmd("pgrep", ["-f", "cloudflared tunnel run --url .* #{tunnel_name}"])

    if String.trim(output) != "" do
      Logger.info("Killing cloudflared process for tunnel #{tunnel_name}")
      {_, _} = System.cmd("pkill", ["-f", "cloudflared tunnel run --url .* #{tunnel_name}"])
    else
      Logger.warn("No running process found for tunnel #{tunnel_name}")
    end

    # Proceed with Cloudflare tunnel deletion
    {output, exit_code} =
      System.cmd("cloudflared", ["tunnel", "delete", tunnel_name], stderr_to_stdout: true)

    if exit_code != 0 do
      Logger.error("Failed to delete tunnel:\n#{output}")
    else
      Logger.info("Tunnel `#{tunnel_name}` deleted successfully.")
    end
  end

  @doc """
  Creates a brand-new tunnel for `subdomain`, sets up a DNS route,
  and **spawns** cloudflared in the background (nohup).

  Persists the new tunnel record in a JSON file so we can track subdomains.
  """
  def add_host(local_server, subdomain) do
    GenServer.cast(__MODULE__, {:add_host, local_server, subdomain})
  end

  @doc """
  Deletes the tunnel for `subdomain` from Cloudflare (cleanup + delete).
  Also removes it from the file. Does NOT stop any background OS process
  you spawned earlier (but you can kill that externally if needed).
  """
  def remove_host(subdomain) do
    GenServer.cast(__MODULE__, {:remove_host, subdomain})
  end

  @doc """
  Get the data about a specific tunnel if it exists in the filesystem
  """
  def get_tunnel_data(ip, port) do
    GenServer.call(__MODULE__, {:get_tunnel_data, ip, port}, 30_000)
  end

  @doc """
    Get DNS Records - We use the set env variables for the zone in order to get this information
  """
  def get_dns_record_details(domain) do
    [api_key: api_key, zone_id: zone_id] = Application.get_env(:sentinel, :cloudflare)

    {:ok, %HTTPoison.Response{body: body, status_code: status}} =
      HTTPoison.get(
        "https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records",
        [Authorization: "Bearer #{api_key}", Accept: "Application/json; Charset=utf-8"],
        recv_timeout: 30_000
      )

    # Return a structure we can use to try and get the relevant record from remote
    case status do
      200 ->
        json = Jason.decode!(body) || %{result: %{}}
        relevant_record = Enum.find(json["result"], fn item -> domain === item["name"] end)

        %{
          success: not is_nil(relevant_record),
          data: relevant_record || %{}
        }

      _ ->
        %{
          success: false,
          data: %{}
        }
    end
  end

  @doc """
    Delete DNS record - we need to leverage the response of the dns records to get the id to remove a record by domain name
  """
  def remove_dns_record(record_details) do
    [api_key: api_key, zone_id: zone_id] = Application.get_env(:sentinel, :cloudflare)

    {:ok, %HTTPoison.Response{status_code: status}} =
      HTTPoison.delete(
        "https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records/#{record_details["id"]}",
        [Authorization: "Bearer #{api_key}", Accept: "Application/json; Charset=utf-8"],
        recv_timeout: 30_000
      )

    # Return a structure we can use to try and get the relevant record from remote
    case status do
      200 ->
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :info,
          message: "Successfully removed the DNS record from CloudFlare"
        })

      _ ->
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :error,
          message: "There was a issue removing the DNS record from CloudFlare: #{record_details.name}"
        })
    end
  end

  @doc """
    Retry make an attempt if the tunnel exists on startup for the host machine.
    Restart the tunnel services persisted in the file system.
  """
  defp retry_until_tunnel_exists(tunnel_name, fun, attempt \\ 1)

  defp retry_until_tunnel_exists(_tunnel_name, _fun, attempt) when attempt > @max_retries do
    Logger.error("Tunnel did not appear after #{@max_retries} attempts.")
  end

  defp retry_until_tunnel_exists(tunnel_name, fun, attempt) do
    if tunnel_exists?(tunnel_name) do
      fun.()
    else
      Logger.warn("Tunnel #{tunnel_name} not found (attempt #{attempt}), retrying...")
      Process.sleep(@retry_delay)
      retry_until_tunnel_exists(tunnel_name, fun, attempt + 1)
    end
  end

  # ----------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------

  defp tunnel_name_for(subdomain),
    do: "sentinel-" <> String.replace(subdomain, ".", "-")

  defp tunnel_exists?(tunnel_name) do
    {output, _exit_code} = System.cmd("cloudflared", ["tunnel", "list"], stderr_to_stdout: true)
    String.contains?(output, tunnel_name)
  end

  # ----------------------------------------------------------------
  # File-based persistence
  # ----------------------------------------------------------------

  defp create_file_if_missing do
    unless file_exists?() do
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
            # expecting a list of records
            {:ok, decoded}

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
      :ok ->
        :ok

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

  defp config_fs do
    Application.get_env(:sentinel, :fs)
  end

  defp config_fs(key), do: config_fs()[key]
end

defmodule Tunneld.Machines.Expose do
  @moduledoc """
  Expose a service running inside a container on a **remote** machine to the
  gateway's local subnet.

  macvlan only spans a single Layer-2 segment, so a container on a machine
  reached over the internet cannot appear as a subnet device. Instead this
  module opens a reverse SSH port-forward (`ssh -L`) from the gateway to the
  container's port on the remote host, then registers an nginx resource whose
  pool points at `127.0.0.1:<forwarded_port>`. The result is that the container
  service becomes reachable subnet-wide at `http://<name>.tunneld.lan:18000`,
  indistinguishable from a local service.

  A forwarded port and its resource live for the lifetime of the container.
  Tunnels are tracked in `expose.json` so they can be torn down when the
  container is deleted or the machine removed.

  In mock mode no SSH tunnel is opened; a resource is registered pointing at a
  local loopback port so the full flow can be exercised on a laptop.
  """

  use GenServer
  require Logger

  alias Tunneld.Machines.Store
  alias Tunneld.Servers.Resources

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @local_bind "127.0.0.1"
  @min_port 20000
  @max_port 30000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Open a reverse SSH tunnel for a container's port and register a resource so
  it is reachable on the subnet. Returns `{:ok, lan_url}` or `{:error, reason}`.
  """
  def expose(machine_id, container, port) do
    GenServer.call(__MODULE__, {:expose, machine_id, container, port}, 30_000)
  end

  @doc "Tear down the tunnel and remove the resource for a container."
  def unexpose(machine_id, container) do
    GenServer.cast(__MODULE__, {:unexpose, machine_id, container})
  end

  @doc "Remove all tunnels/resources for a machine (e.g. on machine removal)."
  def cleanup_machine(machine_id) do
    GenServer.cast(__MODULE__, {:cleanup_machine, machine_id})
  end

  @doc "List active exposures (from disk)."
  def list do
    case Tunneld.Persistence.read_json(path()) do
      {:ok, %{"exposures" => list}} when is_list(list) -> list
      _ -> []
    end
  end

  @doc false
  def mock?, do: @mock

  # --- GenServer ---

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:expose, machine_id, container, port}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(machine_id),
           {:ok, resource} <- create_resource(machine, container, port) do
        {:ok, resource}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:unexpose, machine_id, container}, state) do
    unexpose_impl(machine_id, container)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:cleanup_machine, machine_id}, state) do
    for %{"machine_id" => mid, "container" => container} <- list() do
      if mid == machine_id, do: unexpose_impl(machine_id, container)
    end

    {:noreply, state}
  end

  # --- Implementation ---

  defp create_resource(machine, container, port) do
    name = resource_name(machine, container)
    local_port = allocate_local_port()
    forwarded = "#{@local_bind}:#{local_port}"

    result =
      if @mock do
        Resources.add_share(%{
          "name" => name,
          "description" => "Remote container #{container} on #{machine["name"]}",
          "pool" => [forwarded],
          "expose_source" => "container",
          "expose_machine_id" => machine["id"],
          "expose_container" => container,
          "expose_remote_port" => port,
          "expose_local_port" => local_port
        })
      else
        case open_tunnel(machine, container, port, local_port) do
          :ok ->
            Resources.add_share(%{
              "name" => name,
              "description" => "Remote container #{container} on #{machine["name"]}",
              "pool" => [forwarded],
              "expose_source" => "container",
              "expose_machine_id" => machine["id"],
              "expose_container" => container,
              "expose_remote_port" => port,
              "expose_local_port" => local_port
            })

          {:error, reason} ->
            {:error, "failed to open SSH tunnel: #{inspect(reason)}"}
        end
      end

    persist_exposure(machine, container, local_port, port)

    case result do
      {:error, _} = err ->
        err

      _ ->
        lan_url =
          Resources.fetch_shares()
          |> Enum.find(&(&1.name == name))
          |> then(&(if &1, do: &1.lan_url, else: nil))

        {:ok, %{"name" => name, "lan_url" => lan_url, "local_port" => local_port}}
    end
  end

  defp open_tunnel(machine, container, remote_port, local_port) do
    id = machine["id"]
    key = Path.join([Tunneld.Config.fs_root(), "ssh", id])
    host = machine["address"]
    ssh_port = Integer.to_string(machine["ssh_port"] || 22)

    # Resolve the container's IP on the remote host so we can forward to it.
    container_ip = container_ip(machine, container)

    if is_nil(container_ip) or container_ip == "" do
      {:error, :container_ip_unknown}
    else
      args = [
        "-i", key,
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=10",
        "-o", "ExitOnForwardFailure=yes",
        "-f", "-N",
        "-p", ssh_port,
        "-L", "#{@local_bind}:#{local_port}:#{container_ip}:#{remote_port}",
        host
      ]

      case System.cmd("ssh", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {out, code} -> {:error, {:ssh_failed, code, out}}
      end
    end
  end

  defp container_ip(machine, container) do
    case Tunneld.Machines.list_containers(machine["id"]) do
      {:ok, containers} ->
        Enum.find_value(containers, fn c ->
          if c["name"] == container, do: c["ipv4"]
        end)

      _ ->
        nil
    end
  end

  defp unexpose_impl(machine_id, container) do
    records = list()
    resource_name = records |> Enum.find(&(&1["machine_id"] == machine_id and &1["container"] == container))

    resources = Resources.fetch_shares()

    target =
      Enum.find(resources, fn r ->
        r.expose_source == "container" and r.expose_machine_id == machine_id and r.expose_container == container
      end)

    if target do
      Resources.remove_share(target.id)
    end

    if resource_name do
      remove_persisted(machine_id, container)
    end
  end

  defp resource_name(machine, container) do
    # Reuse a persisted name if one already exists for this container, else derive one.
    existing = Enum.find(list(), &(&1["machine_id"] == machine["id"] and &1["container"] == container))

    if existing && existing["name"] do
      existing["name"]
    else
      sanitize("#{machine["name"]}-#{container}")
    end
  end

  defp sanitize(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-zA-Z0-9\-]/, "-")
    |> String.slice(0, 63)
  end

  defp allocate_local_port do
    used =
      for %{"local_port" => p} <- list(), do: p

    @min_port..@max_port
    |> Enum.find(fn p -> p not in used end)
    |> Kernel.||(@min_port)
  end

  defp persist_exposure(machine, container, local_port, remote_port) do
    records = list()

    updated =
      records
      |> Enum.reject(&(&1["machine_id"] == machine["id"] and &1["container"] == container))
      |> Kernel.++([
        %{
          "machine_id" => machine["id"],
          "container" => container,
          "local_port" => local_port,
          "remote_port" => remote_port,
          "name" => resource_name(machine, container)
        }
      ])

    Tunneld.Persistence.write_json(path(), %{"exposures" => updated})
  end

  defp remove_persisted(machine_id, container) do
    records =
      list()
      |> Enum.reject(&(&1["machine_id"] == machine_id and &1["container"] == container))

    Tunneld.Persistence.write_json(path(), %{"exposures" => records})
  end

  defp path do
    Path.join(Tunneld.Config.fs_root(), "expose.json")
  end
end

defmodule Tunneld.Machines do
  @moduledoc """
  Machine registry and SSH-backed control plane for managed Linux boxes.

  Each managed machine is a record in `machines.json`:

      %{
        "id" => "uuid",
        "name" => "human label",
        "address" => "host or ip",
        "ssh_port" => 22,
        "kind" => "incus",
        "location" => "local" | "remote",
        "added_at" => "ISO8601",
        "capabilities" => %{...} | nil,
        "last_seen" => "ISO8601" | nil,
        "status" => "enrolled" | "probing" | "ready" | "unreachable"
      }

  `location` distinguishes machines reachable on the gateway's own subnet
  (`"local"`, eligible for macvlan container networking) from machines reached
  over the internet (`"remote"`, containers use a NAT bridge + proxy devices).

  State on disk is a hint. Live state (containers running, capabilities) is
  always queried from the machine over SSH, never trusted from the cache,
  because SSH-managed machines drift outside tunneld's view.

  SSH is shelled out to `ssh` with ControlMaster multiplexing so repeated
  commands (list, exec, probe) reuse one master connection per machine.
  In mock mode (`:mock_data`), no SSH is performed and a fake Incus is
  simulated so the full enroll -> probe -> list loop works on a laptop.
  """

  use GenServer
  require Logger

  alias Tunneld.Machines.{Store, SSH, Provider, Runtime}

  @pubsub_topic "component:machines"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "List all enrolled machines (from disk; status is a hint)."
  def list, do: Store.all()

  @doc "Fetch a single machine by id."
  def get(id), do: Store.get(id)

  @doc """
  Infer whether a machine address is local (on the gateway's own subnet) or
  remote, based on the configured gateway IP.
  """
  def infer_location(address) when is_binary(address) do
    same_subnet?(address, gateway_ip())
  end

  defp gateway_ip do
    case Application.get_env(:tunneld, :network, []) do
      kw when is_list(kw) -> Keyword.get(kw, :gateway)
      map when is_map(map) -> Map.get(map, :gateway) || Map.get(map, "gateway")
      _ -> nil
    end
  end

  # Same subnet heuristic: two IPv4 addresses share the /24 prefix of the
  # gateway. Falls back to :remote when either address can't be parsed.
  defp same_subnet?(address, gateway) do
    with {:ok, a} <- parse_ip4(address),
         {:ok, g} <- parse_ip4(gateway) do
      ({a, g} |> same_prefix?() && "local") || "remote"
    else
      _ -> "remote"
    end
  end

  defp same_prefix?({[a, b, c, _], [a, b, c, _]}), do: true
  defp same_prefix?(_), do: false

  defp parse_ip4(str) do
    case :inet.parse_address(String.to_charlist(str)) do
      {:ok, {a, b, c, d}} -> {:ok, [a, b, c, d]}
      _ -> :error
    end
  end

  @doc """
  Enroll a new machine. Generates an Ed25519 keypair, stores the private
  half on tunneld (mode 600), returns the public half for the operator to
  install on the target. Does not probe yet — call `probe/1` after the
  operator has installed the key.
  """
  def enroll(params) when is_map(params) do
    GenServer.call(__MODULE__, {:enroll, params})
  end

  @doc "Return the public key string the operator must install on the target."
  def public_key(id), do: GenServer.call(__MODULE__, {:public_key, id})

  @doc """
  Probe a machine's capabilities over SSH (or mock). Stores the result
  against the machine record and broadcasts an update.
  """
  def probe(id), do: GenServer.call(__MODULE__, {:probe, id}, 30_000)

  @doc "List listening sockets on a machine (runtime-agnostic, live over SSH or mock)."
  def listeners(id), do: GenServer.call(__MODULE__, {:listeners, id}, 30_000)

  @doc "Install Incus on a machine, then probe it. Returns `{:ok, machine}` or `{:error, reason}`."
  def install_incus(id), do: GenServer.call(__MODULE__, {:install_incus, id}, 120_000)

  @doc "List containers/VMs on a machine (live, over SSH or mock)."
  def list_containers(id), do: GenServer.call(__MODULE__, {:list_containers, id}, 30_000)

  @doc "Create a container/VM on a machine. `spec` is a map with name, image, type, cpu, memory, ports."
  def create_container(id, spec),
    do: GenServer.call(__MODULE__, {:create_container, id, spec}, 60_000)

  @doc "Start a container/VM on a machine."
  def start_container(id, name),
    do: GenServer.call(__MODULE__, {:start_container, id, name}, 30_000)

  @doc "Stop a container/VM on a machine."
  def stop_container(id, name),
    do: GenServer.call(__MODULE__, {:stop_container, id, name}, 30_000)

  @doc "Delete a container/VM on a machine."
  def delete_container(id, name),
    do: GenServer.call(__MODULE__, {:delete_container, id, name}, 30_000)

  @doc "Remove a machine from the registry and delete its keypair."
  def remove(id), do: GenServer.call(__MODULE__, {:remove, id})

  @doc "Subscribe to machine updates (PubSub)."
  def subscribe do
    Phoenix.PubSub.subscribe(Tunneld.PubSub, @pubsub_topic)
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, @pubsub_topic, %{
      id: "machines",
      event: event,
      data: payload
    })
  end

  defp validate_spec(%{"name" => name, "image" => image} = spec) do
    cond do
      not is_binary(name) or String.trim(name) == "" ->
        {:error, "name is required"}

      not Regex.match?(~r/^[a-zA-Z0-9\-]{1,63}$/, name) ->
        {:error, "name must be alphanumeric/hyphens, max 63 chars"}

      not is_binary(image) or String.trim(image) == "" ->
        {:error, "image is required"}

      spec["type"] not in [nil, "container", "vm"] ->
        {:error, "type must be container or vm"}

      spec["network"] not in [nil, "bridge", "macvlan"] ->
        {:error, "network must be bridge or macvlan"}

      spec["cpu"] != nil and (not is_integer(spec["cpu"]) or spec["cpu"] < 1) ->
        {:error, "cpu must be a positive integer"}

      spec["memory"] != nil and (not is_integer(spec["memory"]) or spec["memory"] < 1) ->
        {:error, "memory must be a positive integer (MiB)"}

      spec["network"] == "macvlan" and spec["type"] == "vm" ->
        {:error, "macvlan networking is not supported for VMs"}

      true ->
        :ok
    end
  end

  defp validate_spec(%{"image" => _} = spec) when not is_map_key(spec, "name"),
    do: {:error, "name is required"}

  defp validate_spec(%{"name" => _} = spec) when not is_map_key(spec, "image"),
    do: {:error, "image is required"}

  defp validate_spec(_), do: {:error, "name and image are required"}

  # --- GenServer ---

  @impl true
  def init(_) do
    # On startup, asynchronously probe every enrolled machine, install Incus
    # where it is missing, and refresh status so the dashboard reflects live
    # state without a manual probe. Runs in a Task so the supervision tree is
    # not blocked by slow SSH round-trips on a cold boot.
    Task.start(fn -> recover_machines() end)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:enroll, params}, _from, _state) do
    name = String.trim(params["name"] || "")
    address = String.trim(params["address"] || "")
    ssh_port = params["ssh_port"] || 22
    ssh_user = String.trim(params["ssh_user"] || "root")
    kind = params["kind"] || "incus"
    location = params["location"] || infer_location(address)

    cond do
      name == "" ->
        {:reply, {:error, "name is required"}, %{}}

      address == "" ->
        {:reply, {:error, "address is required"}, %{}}

      location not in ["local", "remote"] ->
        {:reply, {:error, "location must be local or remote"}, %{}}

      true ->
        id = UUID.uuid4()
        {pub, priv} = SSH.generate_keypair()
        :ok = SSH.store_key(id, priv)

        record = %{
          "id" => id,
          "name" => name,
          "address" => address,
          "ssh_port" => ssh_port,
          "ssh_user" => ssh_user,
          "kind" => kind,
          "location" => location,
          "added_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "capabilities" => nil,
          "last_seen" => nil,
          "status" => "enrolled"
        }

        :ok = Store.put(record)
        broadcast(:added, record)
        {:reply, {:ok, %{"id" => id, "public_key" => pub, "machine" => record}}, %{}}
    end
  end

  @impl true
  def handle_call({:public_key, id}, _from, state) do
    reply =
      case Store.get(id) do
        {:ok, machine} ->
          {:ok, SSH.public_key_string(machine["id"])}

        {:error, :not_found} ->
          {:error, "not found"}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:probe, id}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id) do
        do_probe(machine)
      end

    {:reply, reply, state}
  end

  def handle_call({:listeners, id}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id),
           {:ok, listeners} <- Runtime.listeners(machine) do
        {:ok, listeners}
      end

    {:reply, reply, state}
  end

  def handle_call({:install_incus, id}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id),
           {:ok, _} <- Provider.install_incus(machine) do
        do_probe(machine)
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:list_containers, id}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id),
           {:ok, containers} <- Provider.list_containers(machine) do
        {:ok, containers}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:create_container, id, spec}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id),
           :ok <- validate_spec(spec),
           {:ok, container} <- Provider.create_container(machine, spec) do
        broadcast(:container_added, %{"machine_id" => id, "container" => container})
        {:ok, container}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:start_container, id, name}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id),
           {:ok, result} <- Provider.start_container(machine, name) do
        broadcast(:container_updated, %{"machine_id" => id, "container" => result})
        {:ok, result}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:stop_container, id, name}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id),
           {:ok, result} <- Provider.stop_container(machine, name) do
        broadcast(:container_updated, %{"machine_id" => id, "container" => result})
        {:ok, result}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete_container, id, name}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id),
           {:ok, result} <- Provider.delete_container(machine, name) do
        broadcast(:container_removed, %{"machine_id" => id, "name" => name})
        {:ok, result}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:remove, id}, _from, state) do
    case Store.get(id) do
      {:error, :not_found} ->
        {:reply, {:error, "not found"}, state}

      {:ok, _record} ->
        :ok = Store.delete(id)
        SSH.delete_key(id)
        broadcast(:removed, %{"id" => id})
        {:reply, :ok, state}
    end
  end

  defp do_probe(machine) do
    with {:ok, caps} <- Provider.probe(machine) do
      updated =
        machine
        |> Map.put("capabilities", caps)
        |> Map.put("last_seen", DateTime.utc_now() |> DateTime.to_iso8601())
        |> Map.put("status", "ready")

      :ok = Store.put(updated)
      broadcast(:updated, updated)
      {:ok, updated}
    end
  end

  # Startup recovery: probe every enrolled machine, install Incus where it is
  # missing, and mark unreachable machines so the dashboard reflects live state
  # without a manual probe. Container restart on a machine reboot is handled by
  # Incus itself (tunneld sets `boot.autostart true` on creation); reverse SSH

  defp recover_machines do
    for machine <- Store.all() do
      id = machine["id"]

      case do_probe(machine) do
        {:ok, _} ->
          :ok

        {:error, :incus_not_installed} ->
          Logger.info("Machine #{id} missing Incus; installing on startup")

          with {:ok, _} <- Provider.install_incus(machine),
               {:ok, _} <- do_probe(machine) do
            :ok
          else
            {:error, reason} -> mark_unreachable(machine, reason)
          end

        {:error, reason} ->
          mark_unreachable(machine, reason)
      end
    end

    :ok
  end

  defp mark_unreachable(machine, reason) do
    Logger.warning("Machine #{machine["id"]} unreachable on startup: #{inspect(reason)}")

    updated =
      machine
      |> Map.put("status", "unreachable")
      |> Map.put("last_seen", DateTime.utc_now() |> DateTime.to_iso8601())

    :ok = Store.put(updated)
    broadcast(:updated, updated)
  end
end

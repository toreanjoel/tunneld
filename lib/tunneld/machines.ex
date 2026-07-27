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
        "added_at" => "ISO8601",
        "capabilities" => %{...} | nil,
        "last_seen" => "ISO8601" | nil,
        "status" => "enrolled" | "probing" | "ready" | "unreachable"
      }

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

  alias Tunneld.Machines.{Store, SSH, Provider}

  @pubsub_topic "component:machines"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "List all enrolled machines (from disk; status is a hint)."
  def list, do: Store.all()

  @doc "Fetch a single machine by id."
  def get(id), do: Store.get(id)

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

  @doc "List containers/VMs on a machine (live, over SSH or mock)."
  def list_containers(id), do: GenServer.call(__MODULE__, {:list_containers, id}, 30_000)

  @doc "Create a container/VM on a machine. `spec` is a map with name, image, type, cpu, memory, ports."
  def create_container(id, spec), do: GenServer.call(__MODULE__, {:create_container, id, spec}, 60_000)

  @doc "Start a container/VM on a machine."
  def start_container(id, name), do: GenServer.call(__MODULE__, {:start_container, id, name}, 30_000)

  @doc "Stop a container/VM on a machine."
  def stop_container(id, name), do: GenServer.call(__MODULE__, {:stop_container, id, name}, 30_000)

  @doc "Delete a container/VM on a machine."
  def delete_container(id, name), do: GenServer.call(__MODULE__, {:delete_container, id, name}, 30_000)

  @doc "Remove a machine from the registry and delete its keypair."
  def remove(id), do: GenServer.call(__MODULE__, {:remove, id})

  @doc "Subscribe to machine updates (PubSub)."
  def subscribe do
    Phoenix.PubSub.subscribe(Tunneld.PubSub, @pubsub_topic)
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, @pubsub_topic, %{id: "machines", event: event, data: payload})
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

      spec["cpu"] != nil and (not is_integer(spec["cpu"]) or spec["cpu"] < 1) ->
        {:error, "cpu must be a positive integer"}

      spec["memory"] != nil and (not is_integer(spec["memory"]) or spec["memory"] < 1) ->
        {:error, "memory must be a positive integer (MiB)"}

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
    {:ok, %{}}
  end

  @impl true
  def handle_call({:enroll, params}, _from, _state) do
    name = String.trim(params["name"] || "")
    address = String.trim(params["address"] || "")
    ssh_port = params["ssh_port"] || 22
    kind = params["kind"] || "incus"

    cond do
      name == "" ->
        {:reply, {:error, "name is required"}, %{}}

      address == "" ->
        {:reply, {:error, "address is required"}, %{}}

      true ->
        id = UUID.uuid4()
        {pub, priv} = SSH.generate_keypair()
        :ok = SSH.store_key(id, priv)

        record = %{
          "id" => id,
          "name" => name,
          "address" => address,
          "ssh_port" => ssh_port,
          "kind" => kind,
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
        nil -> {:error, "not found"}
        _ -> {:ok, SSH.public_key_string(id)}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:probe, id}, _from, state) do
    reply =
      with {:ok, machine} <- Store.get(id),
           {:ok, caps} <- Provider.probe(machine) do
        updated =
          machine
          |> Map.put("capabilities", caps)
          |> Map.put("last_seen", DateTime.utc_now() |> DateTime.to_iso8601())
          |> Map.put("status", "ready")

        :ok = Store.put(updated)
        broadcast(:updated, updated)
        {:ok, updated}
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
      nil ->
        {:reply, {:error, "not found"}, state}

      _ ->
        :ok = Store.delete(id)
        SSH.delete_key(id)
        broadcast(:removed, %{"id" => id})
        {:reply, :ok, state}
    end
  end
end
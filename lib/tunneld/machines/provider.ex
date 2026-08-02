defmodule Tunneld.Machines.Provider do
  @moduledoc """
  Provider abstraction over managed-machine hypervisors.

  v1 has one implementation: Incus on Linux, driven over SSH. The `kind`
  field on each machine record selects the provider; future providers
  (Hyper-V on Windows, etc.) slot in by adding clauses to `dispatch/1`.

  State is remote and authoritative: every call goes over SSH to the
  machine and returns live state. The machine record on disk is only a
  hint (name, address, capabilities at last probe) and is never trusted
  for "what is running right now".
  """

  alias Tunneld.Machines.SSH

  @doc "Probe a machine's capabilities (Incus version, storage, CPU, memory, KVM, GPU)."
  def probe(machine) do
    kind = machine["kind"] || "incus"
    dispatch(kind, :probe, machine)
  end

  @doc "List containers/VMs on a machine (live)."
  def list_containers(machine) do
    kind = machine["kind"] || "incus"
    dispatch(kind, :list_containers, machine)
  end

  @doc "Create a container or VM on a machine. `spec` is a map with name, image, type, cpu, memory, ports."
  def create_container(machine, spec) do
    kind = machine["kind"] || "incus"
    dispatch(kind, :create_container, machine, spec)
  end

  @doc "Start a container/VM on a machine."
  def start_container(machine, name) do
    kind = machine["kind"] || "incus"
    dispatch(kind, :start_container, machine, name)
  end

  @doc "Stop a container/VM on a machine."
  def stop_container(machine, name) do
    kind = machine["kind"] || "incus"
    dispatch(kind, :stop_container, machine, name)
  end

  @doc "Delete a container/VM on a machine."
  def delete_container(machine, name) do
    kind = machine["kind"] || "incus"
    dispatch(kind, :delete_container, machine, name)
  end

  @doc "Check whether the provider binary is installed on the machine."
  def installed?(machine) do
    kind = machine["kind"] || "incus"
    dispatch(kind, :installed?, machine)
  end

  defp dispatch("incus", :probe, machine) do
    with {:ok, _present} <- incus_installed?(machine),
         {:ok, version} <- run(machine, "incus version"),
         {:ok, storage} <- run(machine, "incus storage list --format json"),
         {:ok, cpus} <- run(machine, "nproc"),
         {:ok, mem} <- run(machine, "free -m | awk '/^Mem:/ {print $2}'"),
         {:ok, kvm} <- run(machine, "lscpu | grep -i kvm"),
         {:ok, gpu} <- run(machine, "lspci | grep -i vga"),
         {:ok, os} <- run(machine, "cat /etc/os-release | grep ^PRETTY_NAME") do
      {:ok, %{
        "provider" => "incus",
        "incus_version" => String.trim(version),
        "storage" => parse_storage(storage),
        "cpu_count" => String.trim(cpus) |> String.to_integer(),
        "memory_mb" => String.trim(mem) |> String.to_integer(),
        "kvm" => String.contains?(kvm, "kvm") or String.contains?(kvm, "KVM"),
        "gpu" => String.trim(gpu) != "",
        "os" => os |> String.replace_prefix("PRETTY_NAME=", "") |> String.trim() |> String.trim("\"")
      }}
    end
  end

  defp dispatch("incus", :list_containers, machine) do
    case run(machine, "incus list --format json") do
      {:ok, raw} ->
        case Jason.decode(raw) do
          {:ok, list} when is_list(list) -> {:ok, normalize_incus_list(list)}
          _ -> {:ok, []}
        end

      {:error, _} = e ->
        e
    end
  end

  defp dispatch("incus", :installed?, machine) do
    case run(machine, "test -x /usr/bin/incus && echo yes || echo no") do
      {:ok, "yes" <> _} -> {:ok, true}
      {:ok, "no" <> _} -> {:ok, false}
      _ -> {:error, :probe_failed}
    end
  end

  defp dispatch(kind, _op, _machine), do: {:error, {:unsupported_provider, kind}}

  defp dispatch("incus", :create_container, machine, spec) do
    name = spec["name"]
    image = spec["image"]
    type = spec["type"] || "container"
    cpu = spec["cpu"]
    memory = spec["memory"]
    ports = spec["ports"] || []
    network = spec["network"] || "bridge"
    vm_flag = if type == "vm", do: " --vm", else: ""

    with {:ok, _} <- run(machine, "incus init #{sh(image)} #{sh(name)}#{vm_flag}"),
         :ok <- maybe_config(machine, name, cpu, memory),
         :ok <- maybe_network(machine, name, network),
         :ok <- add_proxy_devices(machine, name, ports),
         {:ok, _} <- run(machine, "incus config set #{sh(name)} boot.autostart true"),
         {:ok, _} <- run(machine, "incus start #{sh(name)}") do
      {:ok, %{"name" => name, "status" => "Running", "type" => type, "network" => network}}
    end
  end

  defp dispatch("incus", :start_container, machine, name) do
    case run(machine, "incus start #{sh(name)}") do
      {:ok, _} -> {:ok, %{"name" => name, "status" => "Running"}}
      err -> err
    end
  end

  defp dispatch("incus", :stop_container, machine, name) do
    case run(machine, "incus stop #{sh(name)}") do
      {:ok, _} -> {:ok, %{"name" => name, "status" => "Stopped"}}
      err -> err
    end
  end

  defp dispatch("incus", :delete_container, machine, name) do
    with {:ok, _} <- run(machine, "incus stop #{sh(name)} 2>/dev/null || true"),
         {:ok, _} <- run(machine, "incus delete --force #{sh(name)}") do
      {:ok, %{"name" => name, "status" => "deleted"}}
    end
  end

  defp dispatch(kind, _op, _machine, _spec), do: {:error, {:unsupported_provider, kind}}

  defp incus_installed?(machine) do
    case dispatch("incus", :installed?, machine) do
      {:ok, true} -> {:ok, true}
      {:ok, false} -> {:error, :incus_not_installed}
      err -> err
    end
  end

  defp run(machine, command) do
    SSH.run(machine, command)
  end

  # Shell-quote a value for safe interpolation into an ssh command string.
  # Wraps in single quotes and escapes embedded single quotes.
  defp sh(nil), do: "''"
  defp sh(s) when is_binary(s) do
    "'" <> String.replace(s, "'", "'\\''") <> "'"
  end
  defp sh(n) when is_integer(n), do: Integer.to_string(n)

  defp maybe_config(_machine, _name, cpu, memory) when is_nil(cpu) and is_nil(memory), do: :ok
  defp maybe_config(machine, name, cpu, memory) do
    cpu_cmd = if cpu, do: "incus config set #{sh(name)} limits.cpu #{sh(cpu)}", else: "true"
    mem_str = if is_integer(memory), do: "#{memory}MiB", else: nil
    mem_cmd = if mem_str, do: "incus config set #{sh(name)} limits.memory #{sh(mem_str)}", else: "true"

    case run(machine, "#{cpu_cmd} && #{mem_cmd}") do
      {:ok, _} -> :ok
      err -> err
    end
  end

  # Attach the container to a network.
  #
  # macvlan: the container gets its own MAC + DHCP lease straight from the
  # gateway's dnsmasq, appearing on the subnet as an independent device. Only
  # valid for containers (not VMs) on local targets.
  #
  # bridge (default): NAT'd behind the target host; services are reached via
  # Incus proxy devices on the host's IP.
  defp maybe_network(_machine, _name, "bridge"), do: :ok
  defp maybe_network(machine, name, "macvlan") do
    case run(machine, "incus config device add #{sh(name)} eth0 nic network=lxdbr0 nictype=macvlan") do
      {:ok, _} -> :ok
      err -> err
    end
  end
  defp maybe_network(_machine, _name, _), do: :ok

  # Each port: %{"host" => 8080, "container" => 80}
  # Incus proxy device: incus config device add <c> <name> proxy listen=0.0.0.0:<host> connect=0.0.0.0:<container>
  defp add_proxy_devices(_machine, _name, []), do: :ok
  defp add_proxy_devices(machine, name, ports) do
    ports
    |> Enum.reduce_while(:ok, fn %{"host" => host, "container" => container}, _acc ->
      dev_name = "proxy_#{host}"
      cmd = "incus config device add #{sh(name)} #{sh(dev_name)} proxy listen=0.0.0.0:#{host} connect=0.0.0.0:#{container}"

      case run(machine, cmd) do
        {:ok, _} -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp parse_storage(raw) do
    case Jason.decode(raw) do
      {:ok, list} when is_list(list) ->
        Enum.map(list, fn s -> %{"name" => s["name"], "driver" => s["driver"]} end)

      _ -> []
    end
  end

  defp normalize_incus_list(list) do
    Enum.map(list, fn c ->
      ipv4 = c["ipv4"] || extract_ipv4(c["state"]) || ""
      %{
        "name" => c["name"],
        "status" => c["status"],
        "type" => c["type"],
        "ipv4" => ipv4
      }
    end)
  end

  defp extract_ipv4(nil), do: nil
  defp extract_ipv4(state) when is_list(state) do
    case Enum.find(state, &Map.has_key?(&1, "ipv4")) do
      nil -> nil
      entry -> entry["ipv4"]
    end
  end
  defp extract_ipv4(%{"ipv4" => ip}), do: ip
  defp extract_ipv4(_), do: nil
end
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
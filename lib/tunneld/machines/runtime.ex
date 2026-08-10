defmodule Tunneld.Machines.Runtime do
  @moduledoc """
  Runtime-agnostic discovery of what is listening on a managed machine.

  This is the generalization at the heart of tunneld: **a resource is an
  address, not a container.** We never ask "what runtime is this?" — we ask
  "what is listening?". A single `ss -tlnp` enumerates every listening socket
  and its owning process on any Linux host, whether the thing behind it is
  Docker, Incus, systemd, a Go binary in tmux, or a runtime that has not been
  invented yet.

  `listeners/1` returns parsed listener maps. If a container runtime is
  detected (`incus list` / `docker ps`), listeners are *annotated* with the
  container that owns them so the UI can group by runtime — but discovery is
  never gated on a runtime being present. A bare box running a plain systemd
  service works identically to one running Incus.

  `probe/1` is the generic capability probe: OS, kernel, architecture, CPU,
  memory, and a `detected_runtimes` list. It contains no Incus-specific
  fields (the legacy Incus probe was removed with the container CRUD).
  """

  alias Tunneld.Machines.SSH

  @doc """
  Enumerate listening sockets on a machine over SSH. Runtime-agnostic.

  Returns `{:ok, [listener]}` where each listener is:

      %{"addr" => "0.0.0.0", "port" => 3000, "proc" => "node",
        "pid" => 1234, "container" => "whisper" | nil}

  `container` is annotated when a container runtime owns the socket; `nil`
  otherwise. Never blocks discovery on a runtime check failing.
  """
  def listeners(machine) do
    with {:ok, ss_out} <- run(machine, "ss -tlnp 2>/dev/null || ss -tln 2>/dev/null") do
      runtime_map = container_runtime_map(machine)
      parsed = parse_listeners(ss_out, runtime_map)
      # Classify each listener as infrastructure or user/app
      classified = Enum.map(parsed, &classify_listener/1)
      {:ok, classified}
    end
  end

  @infrastructure_procs ~w(sshd caddy systemd-resolve dnsmasq chronyd cupsd avahi rpcbind postfix)

  defp classify_listener(listener) do
    proc = listener["proc"] || ""
    addr = listener["addr"] || ""

    listener
    |> Map.put("infrastructure", infrastructure?(proc))
    |> Map.put("loopback", loopback?(addr))
  end

  defp infrastructure?(proc) do
    Enum.any?(@infrastructure_procs, &String.contains?(proc, &1))
  end

  # The whole 127.0.0.0/8 block is loopback, not just 127.0.0.1 - systemd-resolve
  # famously binds 127.0.0.53. A loopback-only bind is not reachable from the LAN,
  # so it cannot be turned into a resource without extra plumbing.
  defp loopback?("127." <> _), do: true
  defp loopback?(addr) when addr in ["::1", "[::1]"], do: true
  defp loopback?(_), do: false

  @doc """
  Generic capability probe: OS, kernel, arch, CPU, memory, detected runtimes.
  No container-runtime fields.
  """
  def probe(machine) do
    with {:ok, os} <- run(machine, "cat /etc/os-release | grep ^PRETTY_NAME"),
         {:ok, kernel} <- run(machine, "uname -r"),
         {:ok, arch} <- run(machine, "uname -m"),
         {:ok, cpus} <- run(machine, "nproc"),
         {:ok, mem} <- run(machine, "free -m | awk '/^Mem:/ {print $2}'") do
      {:ok,
       %{
         "os" =>
           os |> String.replace_prefix("PRETTY_NAME=", "") |> String.trim() |> String.trim("\""),
         "kernel" => String.trim(kernel),
         "arch" => String.trim(arch),
         "cpu_count" => String.trim(cpus) |> String.to_integer(),
         "memory_mb" => String.trim(mem) |> String.to_integer(),
         "detected_runtimes" => detected_runtimes(machine)
       }}
    end
  end

  @doc "Detect which container runtimes are installed/present on the machine."
  def detected_runtimes(machine) do
    for {runtime, cmd} <- [
          {"incus", "test -x /usr/bin/incus && echo yes || echo no"},
          {"docker", "test -x /usr/bin/docker && echo yes || echo no"},
          {"podman", "test -x /usr/bin/podman && echo yes || echo no"}
        ] do
      case run(machine, cmd) do
        {:ok, out} -> if String.trim(out) == "yes", do: runtime
        _ -> nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  # Build a map of container-name -> %{name, type} when a runtime is present.
  # Tolerates failure so discovery never depends on a runtime.
  defp container_runtime_map(machine) do
    container_list =
      case run(
             machine,
             "incus list --format json 2>/dev/null || docker ps --format json 2>/dev/null"
           ) do
        {:ok, raw} ->
          case Jason.decode(raw) do
            {:ok, list} when is_list(list) -> list
            {:ok, _} -> []
            _ -> []
          end

        _ ->
          []
      end

    Map.new(container_list, fn c ->
      {container_key(c), %{"name" => c["name"], "type" => c["type"] || "container"}}
    end)
  end

  defp container_key(c), do: c["name"]

  # Parse `ss -tlnp` output into listener maps. The container map lets us
  # annotate sockets owned by a container process.
  defp parse_listeners(ss_out, container_map) do
    ss_out
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.drop_while(&(not String.starts_with?(&1, "State")))
    |> Enum.drop(1)
    |> Enum.map(fn line -> parse_line(line, container_map) end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_line(line, container_map) do
    # ss -tlnp columns: State Recv-Q Send-Q Local Peer Process
    parts = String.split(line, ~r/\s+/, trim: true)

    case parts do
      [state, _recv, _send, local, _peer | process_parts] when state == "LISTEN" ->
        {addr, port} = parse_local(local)

        if port do
          proc = parse_process(process_parts)
          pid = proc && proc.pid
          container = proc && Map.get(container_map, proc.name)

          %{
            "addr" => addr,
            "port" => port,
            "proc" => proc && proc.name,
            "pid" => pid,
            "container" => container && container["name"]
          }
        end

      _ ->
        nil
    end
  end

  # Parse "0.0.0.0:3000", "[::]:80", "127.0.0.53:53", "*:22"
  defp parse_local(local) do
    case Regex.run(~r/^([^:]+):(\d+)$/, local) do
      [_, addr, port] ->
        {addr, String.to_integer(port)}

      _ ->
        case Regex.run(~r/^[^\]]*\](?::(\d+))?$/, local) do
          [_, port] -> {"[::]", if(port, do: String.to_integer(port), else: nil)}
          _ -> {"*", nil}
        end
    end
  end

  # Parse process column: users:(("nginx",pid=1234,fd=6),("worker",pid=99))
  defp parse_process(parts) do
    joined = Enum.join(parts, " ")

    case Regex.run(~r/\("([^"]+)",pid=(\d+)/, joined) do
      [_, name, pid] -> %{name: name, pid: String.to_integer(pid)}
      _ -> nil
    end
  end

  defp run(machine, command) do
    SSH.run(machine, command)
  end
end

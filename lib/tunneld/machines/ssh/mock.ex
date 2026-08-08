defmodule Tunneld.Machines.SSH.Mock do
  @moduledoc """
  Simulated SSH target for development without a real Linux+Incus box.

  Recognises the small set of commands the Provider module issues
  (incus version/list/storage, nproc, free, lscpu, lspci, init/start/stop/delete,
  config set, config device add) and returns plausible output so the full
  enroll -> probe -> create -> list loop works end-to-end on a laptop with
  `MOCK_DATA=1`.

  Created containers are tracked in an Agent so subsequent `incus list` calls
  reflect them — simulating real Incus state without a real daemon.
  """

  require Logger

  @doc "Mock run of a command on a fake Incus host."
  def run(_machine, command, _opts) do
    {:ok, mock_output(command)}
  end

  defp mock_output("incus version") do
    "Incus 6.0.0\n"
  end

  defp mock_output("incus list --format json") do
    Jason.encode!(__MODULE__.MockState.all())
  end

  defp mock_output("incus storage list --format json") do
    Jason.encode!([%{"name" => "default", "driver" => "dir", "used_by" => 2}])
  end

  defp mock_output("nproc") do
    "4\n"
  end

  defp mock_output("free -m | awk '/^Mem:/ {print $2}'") do
    "8192\n"
  end

  defp mock_output("lscpu | grep -i kvm || true") do
    "Virtualization: kvm\n"
  end

  defp mock_output("ip route | awk '/^default/ {print $5; exit}'") do
    "eth0\n"
  end

  defp mock_output("lspci | grep -i vga || true") do
    ""
  end

  defp mock_output("test -x /usr/bin/incus && echo yes || echo no") do
    "yes\n"
  end

  defp mock_output("cat /etc/os-release | grep ^PRETTY_NAME") do
    "PRETTY_NAME=\"Ubuntu 24.04 LTS\"\n"
  end

  defp mock_output("grep -E '^(ID|ID_LIKE)=' /etc/os-release") do
    "ID=ubuntu\nID_LIKE=debian\n"
  end

  # init: parse "incus init <image> <name> [--vm]"
  defp mock_output("incus init " <> rest) do
    {name, type} =
      if String.contains?(rest, "--vm") do
        parts = rest |> String.replace(" --vm", "") |> String.trim() |> String.split()
        {List.last(parts), "virtual-machine"}
      else
        parts = String.split(rest)
        {List.last(parts), "container"}
      end

    name = unquote_name(name)

    :ok =
      __MODULE__.MockState.add(%{
        "name" => name,
        "status" => "Stopped",
        "type" => type,
        "ipv4" => ""
      })

    ""
  end

  defp mock_output("incus start " <> name) do
    name = name |> String.trim() |> unquote_name()
    :ok = __MODULE__.MockState.update(name, "Running")
    ""
  end

  defp mock_output("incus stop " <> rest) do
    name = rest |> String.split(" ") |> hd() |> String.trim() |> unquote_name()
    :ok = __MODULE__.MockState.update(name, "Stopped")
    ""
  end

  defp mock_output("incus delete --force " <> name) do
    name = name |> String.trim() |> unquote_name()
    :ok = __MODULE__.MockState.delete(name)
    ""
  end

  defp mock_output("incus config set " <> _rest) do
    ""
  end

  defp mock_output("incus config device add " <> _rest) do
    ""
  end

  defp mock_output(_other) do
    ""
  end

  # Strip single-quote wrapping from a sh-quoted argument: 'foo' -> foo
  defp unquote_name("'" <> rest), do: String.trim_trailing(rest, "'")
  defp unquote_name(other), do: other

  # --- In-memory mock Incus state ---

  defmodule MockState do
    @moduledoc false
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> default_state() end, name: __MODULE__)
    end

    def all do
      Agent.get(__MODULE__, &Map.values/1)
    end

    def add(container) do
      Agent.update(__MODULE__, fn state -> Map.put(state, container["name"], container) end)
      :ok
    end

    def update(name, status) do
      Agent.update(__MODULE__, fn state ->
        case Map.get(state, name) do
          nil -> state
          c -> Map.put(state, name, %{c | "status" => status})
        end
      end)

      :ok
    end

    def delete(name) do
      Agent.update(__MODULE__, fn state -> Map.delete(state, name) end)
      :ok
    end

    defp default_state do
      # Mirrors the real `incus list --format json` shape, where IPv4 addresses
      # are nested under state.network.<iface>.addresses (not a top-level key).
      %{
        "mock-app" => %{
          "name" => "mock-app",
          "status" => "Running",
          "type" => "container",
          "state" => %{
            "network" => %{
              "eth0" => %{
                "addresses" => [
                  %{"family" => "inet", "address" => "10.10.0.42", "scope" => "global"}
                ]
              }
            }
          }
        },
        "mock-vm" => %{
          "name" => "mock-vm",
          "status" => "Stopped",
          "type" => "virtual-machine",
          "state" => %{
            "network" => %{
              "eth0" => %{"addresses" => []}
            }
          }
        }
      }
    end
  end
end

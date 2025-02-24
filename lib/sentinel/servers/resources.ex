defmodule Sentinel.Servers.Resources do
  @moduledoc """
  Periodically gathers system resource usage data and broadcasts it to the Resources component.
  """
  use GenServer
  require Logger

  @interval 5_000

  # Public API to start the GenServer
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_sync()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sync, state) do
    resources = get_resources()
    Phoenix.PubSub.broadcast(Sentinel.PubSub, "component:resources", %{
      id: "resources",
      module: SentinelWeb.Live.Components.Resources,
      data: %{
        resources: resources
      }
    })

    schedule_sync()
    {:noreply, Map.merge(state, resources)}
  end

  defp schedule_sync() do
    :timer.send_after(@interval, :sync)
  end

  def get_resources do
    # Get CPU usage as a percentage (e.g., 50.0 means 50% CPU used).
    cpu = :cpu_sup.util() |> Float.round(1)

    # Get memory usage data.
    mem_data = :memsup.get_system_memory_data() |> Enum.into(%{})

    total_mem = Map.get(mem_data, :total_memory, 1)
    free_mem  = Map.get(mem_data, :available_memory, 0)
    used_mem  = total_mem - free_mem
    # This computes the percentage of memory used.
    mem_percent = used_mem / total_mem * 100 |> Float.round(1)

    # Get disk usage for the root filesystem.
    # The command returns a string like "50%\n".
    {usage_str, 0} = System.cmd("sh", ["-c", "df -k / | tail -1 | awk '{print $5}'"])
    storage_percent =
      usage_str
      |> String.trim()
      |> String.trim_trailing("%")
      |> String.to_integer

    %{cpu: cpu, mem: mem_percent, storage: storage_percent}
  end
end

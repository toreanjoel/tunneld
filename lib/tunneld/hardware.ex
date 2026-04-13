defmodule Tunneld.Hardware do
  @moduledoc """
  Pure-function module for reading hardware data from /sys and /proc on ARM64 SBCs.

  Every function returns a map with `:value`, `:unit`, and `:status` fields
  for consistent status reporting across the dashboard.

  Falls back gracefully when a sysfs path doesn't exist (different ARM64 SoCs
  expose different thermal zone paths). Returns `nil` values in that case.
  """

  @thermal_zone_path "/sys/class/thermal/thermal_zone0/temp"
  @loadavg_path "/proc/loadavg"
  @uptime_path "/proc/uptime"
  @meminfo_path "/proc/meminfo"
  @conntrack_count_path "/proc/sys/net/netfilter/nf_conntrack_count"
  @conntrack_max_path "/proc/sys/net/netfilter/nf_conntrack_max"

  @doc "CPU temperature in celsius with threshold context."
  def cpu_temp do
    if mock?() do
      %{value: 48.3, unit: "celsius", threshold: 80.0, status: "normal",
        note: "Thermal throttling begins at 80°C"}
    else
      case File.read(@thermal_zone_path) do
        {:ok, raw} ->
          millidegrees = raw |> String.trim() |> String.to_integer()
          temp = (millidegrees / 1000.0) |> Float.round(1)
          %{value: temp, unit: "celsius", threshold: 80.0, status: temp_status(temp),
            note: "Thermal throttling begins at 80°C"}

        {:error, _} ->
          %{value: nil, unit: "celsius", threshold: 80.0, status: "unknown",
            note: "Thermal zone not available on this SoC"}
      end
    end
  end

  @doc "Load averages (1m, 5m, 15m) with CPU core count for context."
  def load_averages do
    if mock?() do
      %{value_1m: 0.45, value_5m: 0.38, value_15m: 0.32, cores: 4, status: "normal"}
    else
      case File.read(@loadavg_path) do
        {:ok, raw} ->
          [one, five, fifteen | _] = String.split(raw)
          cores = cpu_cores()
          load_1 = String.to_float(one)
          load_5 = String.to_float(five)
          load_15 = String.to_float(fifteen)
          %{value_1m: load_1, value_5m: load_5, value_15m: load_15, cores: cores,
            status: load_status(load_1, cores)}

        {:error, _} ->
          %{value_1m: nil, value_5m: nil, value_15m: nil, cores: nil, status: "unknown"}
      end
    end
  end

  @doc "System uptime in seconds."
  def uptime do
    if mock?() do
      %{value: 864_000, unit: "seconds", human: "10 days"}
    else
      case File.read(@uptime_path) do
        {:ok, raw} ->
          secs = raw |> String.split() |> hd() |> String.to_float() |> round()
          %{value: secs, unit: "seconds", human: format_uptime(secs)}

        {:error, _} ->
          %{value: nil, unit: "seconds", human: "unknown"}
      end
    end
  end

  @doc "Memory info: total, used, available, swap, with percentages and status."
  def memory_info do
    if mock?() do
      %{total_mb: 1024, used_mb: 412, available_mb: 612,
        swap_total_mb: 0, swap_used_mb: 0, percent: 40.2, status: "normal"}
    else
      case File.read(@meminfo_path) do
        {:ok, raw} ->
          parsed = parse_meminfo(raw)
          total = Map.get(parsed, "MemTotal", 0)
          available = Map.get(parsed, "MemAvailable", 0)
          swap_total = Map.get(parsed, "SwapTotal", 0)
          swap_free = Map.get(parsed, "SwapFree", 0)
          used = total - available
          swap_used = swap_total - swap_free
          percent = if total > 0, do: Float.round(used / total * 100, 1), else: 0.0

          %{total_mb: div(total, 1024), used_mb: div(used, 1024),
            available_mb: div(available, 1024), swap_total_mb: div(swap_total, 1024),
            swap_used_mb: div(swap_used, 1024), percent: percent,
            status: mem_status(percent)}

        {:error, _} ->
          %{total_mb: nil, used_mb: nil, available_mb: nil,
            swap_total_mb: nil, swap_used_mb: nil, percent: nil, status: "unknown"}
      end
    end
  end

  @doc "Root partition disk usage with percentage and status."
  def disk_usage do
    if mock?() do
      %{total_gb: 32, used_gb: 8.2, available_gb: 23.8, percent: 25.6, status: "normal"}
    else
      try do
        {output, 0} = System.cmd("df", ["-k", "/"])
        [_header, data_line | _] = String.split(output, "\n", trim: true)
        parts = String.split(data_line, ~r/\s+/)
        total_kb = Enum.at(parts, 1, "0") |> String.to_integer()
        used_kb = Enum.at(parts, 2, "0") |> String.to_integer()
        available_kb = Enum.at(parts, 3, "0") |> String.to_integer()
        percent_str = Enum.at(parts, 4, "0%") |> String.trim_trailing("%")
        percent = String.to_integer(percent_str) * 1.0

        %{total_gb: Float.round(total_kb / 1_048_576, 1),
          used_gb: Float.round(used_kb / 1_048_576, 1),
          available_gb: Float.round(available_kb / 1_048_576, 1),
          percent: percent, status: disk_status(percent)}

      rescue
        _ ->
          %{total_gb: nil, used_gb: nil, available_gb: nil, percent: nil, status: "unknown"}
      end
    end
  end

  @doc "Per-interface network stats (bytes, errors, dropped) for wlan0 and eth0."
  def interface_stats do
    if mock?() do
      %{
        wlan0: %{rx_bytes: 1_048_576, tx_bytes: 524_288, rx_errors: 0, tx_errors: 0,
                  rx_dropped: 0, tx_dropped: 0, status: "normal"},
        eth0: %{rx_bytes: nil, tx_bytes: nil, rx_errors: nil, tx_errors: nil,
                 rx_dropped: nil, tx_dropped: nil, status: "not connected"}
      }
    else
      interfaces = ["wlan0", "eth0"]
      Map.new(interfaces, fn iface ->
        {String.to_atom(iface), read_interface_stats(iface)}
      end)
    end
  end

  @doc "Connection tracking count and max."
  def conntrack do
    if mock?() do
      %{count: 142, max: 65536, percent: 0.2, status: "normal",
        note: "Connection tracking table usage"}
    else
      count = read_sysfs_integer(@conntrack_count_path)
      max = read_sysfs_integer(@conntrack_max_path)

      percent = if max > 0, do: Float.round(count / max * 100, 1), else: 0.0

      %{count: count, max: max, percent: percent, status: conntrack_status(percent),
        note: "Connection tracking table usage"}
    end
  end

  # --- Private helpers ---

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  defp read_sysfs_integer(path) do
    case File.read(path) do
      {:ok, raw} -> raw |> String.trim() |> String.to_integer()
      {:error, _} -> 0
    end
  end

  defp read_interface_stats(iface) do
    base = "/sys/class/net/#{iface}/statistics/"

    rx_bytes = read_sysfs_integer(base <> "rx_bytes")
    tx_bytes = read_sysfs_integer(base <> "tx_bytes")

    if rx_bytes == 0 and tx_bytes == 0 do
      %{rx_bytes: nil, tx_bytes: nil, rx_errors: nil, tx_errors: nil,
        rx_dropped: nil, tx_dropped: nil, status: "not connected"}
    else
      rx_errors = read_sysfs_integer(base <> "rx_errors")
      tx_errors = read_sysfs_integer(base <> "tx_errors")
      rx_dropped = read_sysfs_integer(base <> "rx_dropped")
      tx_dropped = read_sysfs_integer(base <> "tx_dropped")

      %{rx_bytes: rx_bytes, tx_bytes: tx_bytes, rx_errors: rx_errors,
        tx_errors: tx_errors, rx_dropped: rx_dropped, tx_dropped: tx_dropped,
        status: iface_status(rx_errors, tx_errors, rx_dropped, tx_dropped)}
    end
  end

  defp iface_status(rx_err, tx_err, rx_drop, tx_drop) do
    if rx_err + tx_err + rx_drop + tx_drop > 0, do: "degraded", else: "normal"
  end

  defp cpu_cores do
    case File.read("/proc/cpuinfo") do
      {:ok, raw} ->
        raw |> String.split("\n") |> Enum.count(&String.starts_with?(&1, "processor"))

      {:error, _} ->
        4
    end
  end

  defp parse_meminfo(raw) do
    raw
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ~r/\s+/, parts: 2) do
        [key, value] ->
          clean_key = String.trim_trailing(key, ":")
          # Values are in kB
          case Integer.parse(value) do
            {num, _} -> Map.put(acc, clean_key, num)
            :error -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp temp_status(temp) when temp >= 80.0, do: "critical"
  defp temp_status(temp) when temp >= 70.0, do: "warning"
  defp temp_status(_), do: "normal"

  defp load_status(load_1, cores) when cores > 0 do
    ratio = load_1 / cores
    cond do
      ratio >= 2.0 -> "critical"
      ratio >= 1.0 -> "warning"
      true -> "normal"
    end
  end
  defp load_status(_, _), do: "unknown"

  defp mem_status(percent) when percent >= 95.0, do: "critical"
  defp mem_status(percent) when percent >= 85.0, do: "warning"
  defp mem_status(_), do: "normal"

  defp disk_status(percent) when percent >= 95.0, do: "critical"
  defp disk_status(percent) when percent >= 85.0, do: "warning"
  defp disk_status(_), do: "normal"

  defp conntrack_status(percent) when percent >= 90.0, do: "critical"
  defp conntrack_status(percent) when percent >= 70.0, do: "warning"
  defp conntrack_status(_), do: "normal"

  defp format_uptime(secs) when secs < 3600, do: "#{div(secs, 60)} minutes"
  defp format_uptime(secs) when secs < 86_400, do: "#{div(secs, 3600)} hours"
  defp format_uptime(secs), do: "#{div(secs, 86_400)} days"
end
defmodule Tunneld.Servers.Sqm do
  @moduledoc """
  Manages Smart Queue Management (SQM) using the CAKE qdisc algorithm.

  SQM shapes network traffic to reduce bufferbloat and improve latency
  under load. This module applies `tc` (traffic control) rules to the
  WiFi and Ethernet interfaces, configures CPU steering for packet
  distribution, and disables hardware offloading for accurate shaping.

  Settings are persisted to `sqm.json` and re-applied on startup.
  Supports preset modes ("latency", "balanced") and custom bandwidth limits.
  """
  use GenServer
  require Logger

  @default_state %{"mode" => "off", "up_limit" => "25mbit", "down_limit" => "25mbit"}

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    state =
      case read_file() do
        {:ok, data} ->
          data

        _ ->
          write_file(@default_state)
          @default_state
      end

    # Apply rules on startup if enabled
    if state["mode"] != "off" do
      apply_rules(state)
    end

    {:ok, state}
  end

  @doc """
  Update SQM settings and apply them to the system.
  """
  def set_sqm(params) do
    GenServer.call(__MODULE__, {:set_sqm, params})
  end

  @doc """
  Get current SQM state.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call({:set_sqm, params}, _from, state) do
    new_state = Map.merge(@default_state, params)

    result =
      case new_state["mode"] do
        "off" -> remove_rules()
        _ -> apply_rules(new_state)
      end

    case result do
      :ok ->
        write_file(new_state)

        message =
          case new_state["mode"] do
            "off" -> "SQM rules removed"
            "latency" -> "SQM Latency preset applied (15/5 mbit)"
            "balanced" -> "SQM Balanced preset applied (40/20 mbit)"
            _ -> "SQM set to #{new_state["up_limit"]} up / #{new_state["down_limit"]} down"
          end

        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :info,
          message: message
        })

        Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:details", %{
          type: :info,
          message: message
        })

        {:reply, :ok, new_state}

      {:error, reason} ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Failed to update SQM: #{reason}"
        })

        {:reply, {:error, reason}, state}
    end
  end

  defp apply_rules(state) do
    with wan when not is_nil(wan) <- get_net_config(:wlan),
         lan when not is_nil(lan) <- get_net_config(:eth) do
      up = state["up_limit"]
      down = state["down_limit"]

      with {_, 0} <- exec("iw", ["dev", wan, "set", "power_save", "off"]),
           :ok <- set_offloading([wan, lan], "off"),
           :ok <- set_cpu_steering(wan, "f"),
           :ok <- set_cpu_steering(lan, "f"),
           _ <- exec("tc", ["qdisc", "del", "dev", wan, "root"]),
           _ <- exec("tc", ["qdisc", "del", "dev", lan, "root"]),
           {_, 0} <-
             exec("tc", [
               "qdisc",
               "add",
               "dev",
               wan,
               "root",
               "cake",
               "bandwidth",
               up,
               "nat",
               "conservative"
             ]),
           {_, 0} <-
             exec("tc", ["qdisc", "add", "dev", lan, "root", "cake", "bandwidth", down, "nat", "wash", "ethernet"]) do
        Logger.info("SQM applied: UP=#{up}, DOWN=#{down}")
        :ok
      else
        {out, code} -> {:error, "Command failed with code #{code}: #{out}"}
        error -> error
      end
    else
      _ ->
        Logger.error("SQM: Network interfaces not configured. Skipping rule application.")
        :error
    end
  end

  defp remove_rules do
    with wan when not is_nil(wan) <- get_net_config(:wlan),
         lan when not is_nil(lan) <- get_net_config(:eth) do
      exec("tc", ["qdisc", "del", "dev", wan, "root"])
      exec("tc", ["qdisc", "del", "dev", lan, "root"])
      set_offloading([wan, lan], "on")
      set_cpu_steering(wan, "0")
      set_cpu_steering(lan, "0")

      Logger.info("SQM rules removed")
      :ok
    else
      _ ->
        Logger.error("SQM: Network interfaces not configured. Skipping rule removal.")
        :error
    end
  end

  defp exec(cmd, args) do
    if mock?() do
      Logger.debug("[SQM MOCK] Executing: #{cmd} #{Enum.join(args, " ")}")
      {"", 0}
    else
      System.cmd(cmd, args, stderr_to_stdout: true)
    end
  end

  defp set_offloading(devs, mode) do
    Enum.each(devs, fn dev ->
      exec("ethtool", ["-K", dev, "gro", mode, "gso", mode, "tso", mode, "ufo", mode, "lro", mode])
    end)
    :ok
  end

  defp set_cpu_steering(dev, val) do
    rps_paths = Path.wildcard("/sys/class/net/#{dev}/queues/*/rps_cpus")
    xps_paths = Path.wildcard("/sys/class/net/#{dev}/queues/*/xps_cpus")
    all_paths = rps_paths ++ xps_paths

    if mock?() do
      Logger.debug("[SQM MOCK] Writing '#{val}' to #{length(all_paths)} CPU steering paths for #{dev}")
      :ok
    else
      Enum.each(all_paths, &File.write(&1, val))
      :ok
    end
  end

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  # --- Persistence Helpers ---

  defp read_file do
    path = path()
    if is_binary(path) and File.exists?(path) do
      with {:ok, body} <- File.read(path),
           {:ok, json} <- Jason.decode(body),
           do: {:ok, json}
    else
      {:error, :not_found}
    end
  end

  defp write_file(data) do
    case path() do
      path when is_binary(path) -> File.write(path, Jason.encode!(data))
      _ -> {:error, :no_path_configured}
    end
  end

  @doc """
  Check if the SQM configuration file exists.
  """
  def file_exists?(), do: is_binary(path()) and File.exists?(path())

  @doc """
  Get the path to the SQM configuration file.
  """
  def path() do
    root = config_fs(:root)
    sqm = config_fs(:sqm)
    if root && sqm, do: Path.join(root, sqm), else: nil
  end

  defp config_fs(key) do
    case Application.get_env(:tunneld, :fs) do
      kw when is_list(kw) -> Keyword.get(kw, key)
      map when is_map(map) -> Map.get(map, key) || Map.get(map, to_string(key))
      _ -> nil
    end
  end

  defp get_net_config(key) do
    config = Application.get_env(:tunneld, :network, [])

    case config[key] do
      nil ->
        if mock?(), do: (if key == :wlan, do: "wlan0", else: "eth0"), else: nil
      val ->
        val
    end
  end
end

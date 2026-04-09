defmodule Tunneld.Servers.Wlan do
  @moduledoc """
  The wlan server that will be used to get details and interact with the wlan interface of the operating system.
  """
  use GenServer
  require Logger

  # Define the Wi-Fi interface used for internet
  @wpa_config "/etc/wpa_supplicant/wpa_supplicant.conf"
  @conn_interval_checker 15_000
  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  @doc "Starts the GenServer"
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # We make sure the WP Supplicant is running
    init_wp_supplicant()
    send(self(), :check_connection)
    {:ok, %{}}
  end

  # Disconnect from the current connected wireless network
  @impl true
  def handle_call(:disconnect, _from, state) do
    if mock?() do
      {:reply, :ok, state}
    else
      # Disconnect from current network
      run_cmd("wpa_cli", ["-i", Application.get_env(:tunneld, :network)[:wlan], "disconnect"])

      Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
        type: :info,
        message: "Disconnected from network"
      })

      Logger.info("Disconnected from network")

      # send relevant events to the main dashboard
      check_connection()
      {:reply, :ok, state}
    end
  end

  # Scans for networks
  @impl true
  def handle_cast(:scan, state) do
    if mock?() do
      {:noreply, Tunneld.Servers.FakeData.Wlan.get_data()}
    else
      Logger.info("Scanning for Wi-Fi networks...")

      # scan for networks
      run_cmd("wpa_cli", ["scan"])
      {output, _} = run_cmd("wpa_cli", ["scan_results"])

      networks =
        output
        |> String.split("\n")
        |> Enum.map(&parse_scan_result/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(fn i -> i.security !== "/" end)

      # attempt to get current network details
      run_cmd("wpa_cli", ["status"])
      {status_output, _} = run_cmd("wpa_cli", ["status"])

      # Broadcast to the live view (or parent) so it can update the Devices component.
      # Use an id that matches the one used in your live_component render.
      Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:details", %{
        id: "sidebar_details",
        module: TunneldWeb.Live.Components.Sidebar.Details,
        data: %{
          networks: networks,
          info: parse_wpa_status(status_output)
        }
      })

      {:noreply, state}
    end
  end

  # Connects to a Wi-Fi network and overwrites config
  @impl true
  def handle_cast({:connect, ssid, password}, state) do
    Logger.info("Connecting to Wi-Fi: #{ssid}...")

    network_conf = Application.get_env(:tunneld, :network)
    wlan_iface = network_conf[:wlan]
    country = network_conf[:country] || ""

    # Sanitize inputs to prevent WPA config injection.
    # Escape backslashes and double quotes which could break out of the value fields.
    safe_ssid = sanitize_wpa_value(ssid)
    safe_password = sanitize_wpa_value(password)
    safe_country = sanitize_wpa_value(country)

    new_config = """
    country=#{safe_country}
    ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
    update_config=1

    network={
        ssid="#{safe_ssid}"
        psk="#{safe_password}"
        auth_alg=OPEN
        key_mgmt=WPA-PSK
    }
    """

    :ok = File.write(@wpa_config, new_config)

    init_wp_supplicant()

    run_cmd("wpa_cli", ["-i", wlan_iface, "reconnect"])
    run_cmd("dhcpcd", [wlan_iface])

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: :info,
      message: "Connected to network #{ssid} successfully"
    })

    check_connection()

    {:noreply, state}
  end

  # check the connection status of the current interface
  @impl true
  def handle_info(:check_connection, state) do
    check_connection()
    Process.send_after(self(), :check_connection, @conn_interval_checker)
    {:noreply, state}
  end

  @doc "Scans for available Wi-Fi networks"
  def scan_networks() do
    GenServer.cast(__MODULE__, :scan)
  end

  @doc "Connects to a Wi-Fi network with a password (overwrites config)"
  def connect_with_pass(ssid, password) do
    GenServer.cast(__MODULE__, {:connect, ssid, password})
  end

  @doc "Disconnect from the current connected wireless network"
  def disconnect() do
    GenServer.call(__MODULE__, :disconnect)
  end

  @doc "Returns true if the WLAN interface reports an active connection."
  def connected? do
    if mock?() do
      true
    else
      iface = Application.get_env(:tunneld, :network)[:wlan]

      case run_cmd("iw", ["dev", iface, "link"]) do
        {output, _} -> String.trim(output) != "Not connected."
        _ -> false
      end
    end
  rescue
    _ -> false
  end

  # parse the scan results that we get back from the network scanning
  defp parse_scan_result(line) do
    case String.split(line) do
      [_bssid, _freq, signal, flags | rest] ->
        ssid = Enum.join(rest, " ")

        %{ssid: ssid, security: flags, signal: signal, open: is_open_network?(flags)}

      _ ->
        nil
    end
  end

  # We check if the network is a open network or not
  def is_open_network?(flags) do
    # An open network will only have [ESS] and no WPA/WEP
    not String.contains?(flags, "[WPA") and not String.contains?(flags, "[WEP]")
  end

  # Get the current connection status
  defp check_connection do
    if mock?() do
      :local_development_mode
    else
      {output, _} =
        run_cmd("iw", ["dev", Application.get_env(:tunneld, :network)[:wlan], "link"])

      is_connected =
        case output |> String.trim() do
          "Not connected." -> false
          _ -> true
        end

      Phoenix.PubSub.broadcast(Tunneld.PubSub, "status:internet", %{
        type: :internet,
        status: is_connected
      })

      if(is_connected, do: :connected, else: :disconnected)
    end
  end

  # we reinit the wp supplicant on startup initially
  def init_wp_supplicant() do
    if mock?() do
      :local_development_mode
    else
      Logger.info("Restarting wpa_supplicant...")

      # Kill existing wpa_supplicant
      run_cmd("pkill", ["-f", "wpa_supplicant"])
      # Wait 2 seconds for the process to fully terminate
      Process.sleep(2000)

      # Restart wpa_supplicant
      {_, exit_code} =
        run_cmd("wpa_supplicant", [
          "-B",
          "-i",
          Application.get_env(:tunneld, :network)[:wlan],
          "-c",
          @wpa_config
        ])

      if exit_code == 0 do
        Logger.info("wpa_supplicant restarted successfully")
        # Ensure wpa_cli is ready before proceeding
        wait_for_wpa_cli_ready()
      else
        Logger.error("Failed to restart wpa_supplicant")
      end
    end
  end

  # Ensures wpa_cli is available before proceeding
  defp wait_for_wpa_cli_ready(attempts \\ 5) do
    {output, exit_code} = run_cmd("wpa_cli", ["status"])

    if exit_code == 0 and String.contains?(output, "wpa_state") do
      Logger.info("wpa_cli is ready")
      :ok
    else
      if attempts > 0 do
        Process.sleep(2000)
        wait_for_wpa_cli_ready(attempts - 1)
      else
        Logger.error("Failed to detect wpa_cli readiness after multiple attempts")
        :error
      end
    end
  end

  # Escape characters that could break out of a double-quoted WPA config value.
  defp sanitize_wpa_value(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "")
    |> String.replace("\r", "")
  end

  defp sanitize_wpa_value(_), do: ""

  # Parses raw wpa_cli status output into a map
  def parse_wpa_status(raw) do
    raw
    |> String.split("\n")
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "Selected interface")))
    |> Enum.map(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, val] -> {key, val}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end

  # Wrapper around System.cmd with a timeout to prevent
  # GenServer hangs when system commands stall.
  # Uses spawn instead of Task.async for safe error isolation.
  defp run_cmd(cmd, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 15_000)
    cmd_opts = opts |> Keyword.delete(:timeout) |> Keyword.put_new(:stderr_to_stdout, true)
    caller = self()
    ref = make_ref()

    pid =
      spawn(fn ->
        try do
          result = System.cmd(cmd, args, cmd_opts)
          send(caller, {ref, {:ok, result}})
        rescue
          e -> send(caller, {ref, {:error, e}})
        catch
          _, reason -> send(caller, {ref, {:error, reason}})
        end
      end)

    receive do
      {^ref, {:ok, result}} -> result
      {^ref, {:error, _}} -> {"", 1}
    after
      timeout ->
        Process.exit(pid, :kill)
        {"", 1}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    unless mock?() do
      Logger.info("Wlan shutting down, stopping wpa_supplicant")
      run_cmd("pkill", ["-f", "wpa_supplicant"])
    end

    :ok
  end
end

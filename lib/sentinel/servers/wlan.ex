defmodule Sentinel.Servers.Wlan do
  @moduledoc """
  The wlan server that will be used to get details and interact with the wlan interface of the operating system.
  """
  use GenServer
  require Logger

  # TODO: Add the dynamic from config for the interface and the broadcasting to the UI

  # Define the Wi-Fi interface used for internet
  @interface "wlan1"
  @wpa_config "/etc/wpa_supplicant/wpa_supplicant.conf"
  @conn_interval_checker 15_000

  @doc "Starts the GenServer"
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    # We make sure the WP Supplicant is running
    init_wp_supplicant()
    send(self(), :check_connection)
    {:ok, %{}}
  end

  # Scans for networks
  def handle_call(:scan, _from, state) do
    Logger.info("Scanning for Wi-Fi networks...")
    System.cmd("wpa_cli", ["scan"])
    # Wait for scan results
    Process.sleep(3000)
    {:reply, :ok, state}
  end

  # Fetches scan results and parses SSIDs
  def handle_call(:scan_results, _from, state) do
    {output, _} = System.cmd("wpa_cli", ["scan_results"])

    networks =
      output
      |> String.split("\n")
      |> Enum.map(&parse_scan_result/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn i -> i.security !== "/" end)

    {:reply, networks, state}
  end

  # Checks if a Wi-Fi network is open or secured
  def handle_call({:network_security, ssid}, _from, state) do
    {output, _} = System.cmd("wpa_cli", ["scan_results"])

    security_flags =
      output
      |> String.split("\n")
      |> Enum.find(fn line -> String.contains?(line, ssid) end)

    is_secure =
      case security_flags do
        nil ->
          {:error, "SSID not found"}

        _ ->
          if String.contains?(security_flags, "[WPA") or String.contains?(security_flags, "[WEP") do
            {:secure, true}
          else
            {:secure, false}
          end
      end

    {:reply, is_secure, state}
  end

  # Disconenct from the current connected wireless network
  def handle_call(:disconnect, _from, state) do
    # Disconnect from current network
    System.cmd("wpa_cli", ["-i", @interface, "disconnect"])

    Logger.info("Disconencted from network")
    {:reply, :ok, state}
  end

  # Connects to a Wi-Fi network and overwrites config
  def handle_cast({:connect, ssid, password}, state) do
    Logger.info("Connecting to Wi-Fi: #{ssid}...")

    new_config = """
    country=ZA
    ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
    update_config=1

    network={
        ssid="#{ssid}"
        psk="#{password}"
        auth_alg=OPEN
        key_mgmt=WPA-PSK
    }
    """

    # Overwrite the wpa_supplicant.conf file
    :ok = File.write(@wpa_config, new_config)

    # init with removing any cache or stored info on the prev used config
    init_wp_supplicant()

    # Reconnect to last known network setup
    System.cmd("wpa_cli", ["-i", @interface, "reconnect"])

    # Request new DHCP lease to get an IP
    System.cmd("dhcpcd", [@interface])

    {:noreply, state}
  end

  # check the connection status of the current interface
  def handle_info(:check_connection, state) do
    check_connection()
    Process.send_after(self(), :check_connection, @conn_interval_checker)
    {:noreply, state}
  end

  @doc "Scans for available Wi-Fi networks"
  def scan_networks() do
    GenServer.call(__MODULE__, :scan)
  end

  @doc "Retrieves scanned Wi-Fi networks"
  def get_scan_results() do
    GenServer.call(__MODULE__, :scan_results)
  end

  @doc "Checks if a Wi-Fi network requires a password"
  def get_network_security(ssid) do
    GenServer.call(__MODULE__, {:network_security, ssid})
  end

  @doc "Connects to a Wi-Fi network with a password (overwrites config)"
  def connect_with_pass(ssid, password) do
    GenServer.cast(__MODULE__, {:connect, ssid, password})
  end

  @doc "Disconnect from the current connected wireless network"
  def disconnect() do
    GenServer.call(__MODULE__, :disconnect)
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
    {output, _} = System.cmd("iw", ["dev", @interface, "link"])

    is_connected =
      case output |> String.trim() do
        "Not connected." -> false
        _ -> true
      end

    IO.inspect("Connection: #{inspect(is_connected)}")

    if(is_connected, do: :connected, else: :disconnected)
  end

  # we reinit the wp supplicant on startup initially
  def init_wp_supplicant() do
    Logger.info("Restarting wpa_supplicant...")

    # Kill existing wpa_supplicant
    System.cmd("pkill", ["-f", "wpa_supplicant"])
    Process.sleep(2000)  # Wait 2 seconds for the process to fully terminate

    # Restart wpa_supplicant
    {_, exit_code} = System.cmd("wpa_supplicant", ["-B", "-i", @interface, "-c", @wpa_config])

    if exit_code == 0 do
      Logger.info("wpa_supplicant restarted successfully")
      wait_for_wpa_cli_ready()  # Ensure wpa_cli is ready before proceeding
    else
      Logger.error("Failed to restart wpa_supplicant")
    end
  end

  # Ensures wpa_cli is available before proceeding
  defp wait_for_wpa_cli_ready(attempts \\ 5) do
    {output, exit_code} = System.cmd("wpa_cli", ["status"])

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
end

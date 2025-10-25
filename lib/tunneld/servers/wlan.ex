defmodule Tunneld.Servers.Wlan do
  @moduledoc """
  The wlan server that will be used to get details and interact with the wlan interface of the operating system.
  """
  use GenServer
  require Logger

  # Define the Wi-Fi interface used for internet
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

  # Checks if a Wi-Fi network is open or secured
  def handle_call({:network_security, ssid}, _from, state) do
    if Application.get_env(:tunneld, :mock_data, false) do
      {:reply, {:secure, true}, state}
    else
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
            if String.contains?(security_flags, "[WPA") or
                 String.contains?(security_flags, "[WEP") do
              {:secure, true}
            else
              {:secure, false}
            end
        end

      {:reply, is_secure, state}
    end
  end

  # Disconenct from the current connected wireless network
  def handle_call(:disconnect, _from, state) do
    if Application.get_env(:tunneld, :mock_data, false) do
      {:reply, :ok, state}
    else
      # Disconnect from current network
      System.cmd("wpa_cli", ["-i", Application.get_env(:tunneld, [:network, :wlan]), "disconnect"])

      Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
        type: :info,
        message: "Disconnected from network"
      })

      Logger.info("Disconencted from network")

      # send relevant events to the main dashboard
      check_connection()
      {:reply, :ok, state}
    end
  end

  # Scans for networks
  def handle_cast(:scan, state) do
    if Application.get_env(:tunneld, :mock_data, false) do
      {:noreply, Tunneld.Servers.FakeData.Wlan.get_data()}
    else
      Logger.info("Scanning for Wi-Fi networks...")

      # scan for networks
      System.cmd("wpa_cli", ["scan"])
      {output, _} = System.cmd("wpa_cli", ["scan_results"])

      networks =
        output
        |> String.split("\n")
        |> Enum.map(&parse_scan_result/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(fn i -> i.security !== "/" end)

      # attempt to get current network details
      System.cmd("wpa_cli", ["status"])
      {status_output, _} = System.cmd("wpa_cli", ["status"])

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
  def handle_cast({:connect, ssid, password}, state) do
    Logger.info("Connecting to Wi-Fi: #{ssid}...")

    # TODO: The country and the freq needs to change, freq is a bug but ZA needs to be set on env
    new_config = """
    country=ZA
    ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
    update_config=1

    network={
        ssid="#{ssid}"
        psk="#{password}"
        auth_alg=OPEN
        key_mgmt=WPA-PSK
        freq_list=2412 2437 2462
    }
    """

    # Overwrite the wpa_supplicant.conf file
    :ok = File.write(@wpa_config, new_config)

    # init with removing any cache or stored info on the prev used config
    init_wp_supplicant()

    # Reconnect to last known network setup
    System.cmd("wpa_cli", ["-i", Application.get_env(:tunneld, :network)[:wlan], "reconnect"])

    # Request new DHCP lease to get an IP
    System.cmd("dhcpcd", [Application.get_env(:tunneld, :network)[:wlan]])

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: :info,
      message: "Connected to network #{ssid} successfully"
    })

    # send relevant events to the main dashboard
    check_connection()

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
    GenServer.cast(__MODULE__, :scan)
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
    if Application.get_env(:tunneld, :mock_data, false) do
      :local_development_mode
    else
      {output, _} =
        System.cmd("iw", ["dev", Application.get_env(:tunneld, :network)[:wlan], "link"])

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
    if Application.get_env(:tunneld, :mock_data, false) do
      :local_development_mode
    else
      Logger.info("Restarting wpa_supplicant...")

      # Kill existing wpa_supplicant
      System.cmd("pkill", ["-f", "wpa_supplicant"])
      # Wait 2 seconds for the process to fully terminate
      Process.sleep(2000)

      # Restart wpa_supplicant
      {_, exit_code} =
        System.cmd("wpa_supplicant", [
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
end

defmodule Sentinel.Servers.Wlan do
  @moduledoc """
  The wlan server that will be used to get details and interact with the wlan interface of the operating system
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init and check auth files
  """
  def init(_) do
    {:ok, %{}}
  end

  #  echo 'ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
  # update_config=1
  # country=ZA

  # network={
  #     ssid="YourSSID"
  #     psk="YourPassword"
  #     key_mgmt=WPA-PSK
  #     auth_alg=OPEN
  # }' | tee /etc/wpa_supplicant/wpa_supplicant-wlan1.conf > /dev/null

  # ------ important functions ----

  # check if the device is connected to a router
  # iw dev wlan1 link

  # getting the list wlan devices - this can be used to know what device you want to setup as the ap vs client
  # iw dev

  # Scanning for SSIDs
  # iw dev wlan1 scan | grep SSID

  # add details for the SSID of choice
  # config needs to be made that will be writted to
  # wpa_passphrase "YourSSID" "YourPassword" > /etc/wpa_supplicant/wpa_supplicant-wlan1.conf

  # Restart the wpa_supplicant service after writing to it with the details (starting)
  # wpa_supplicant -B -i wlan1 -c /etc/wpa_supplicant/wpa_supplicant-wlan1.conf

  # Stopping the connection to the wifi connection
  # pkill wpa_supplicant

  # -------------------------------

  # Config helper - we need to set the wlan configuration on the env variables and runtime config?
  # defp config_fs(), do: Application.get_env(:sentinel, :fs)
  # defp config_fs(key), do: config_fs()[key]
  # defp config_auth(), do: Application.get_env(:sentinel, :auth)
  # defp config_auth(key), do: config_auth()[key]
end

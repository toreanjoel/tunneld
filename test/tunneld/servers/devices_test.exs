defmodule Tunneld.Servers.DevicesTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Devices

  setup do
    original_mock = Application.get_env(:tunneld, :mock_data)
    Application.put_env(:tunneld, :mock_data, true)

    on_exit(fn ->
      Application.put_env(:tunneld, :mock_data, original_mock)
    end)

    :ok
  end

  describe "fetch_devices/0" do
    test "returns parsed device list from mock data" do
      devices = Devices.fetch_devices()

      assert is_list(devices)
      assert length(devices) == 2

      [first | _] = devices
      assert Map.has_key?(first, :mac)
      assert Map.has_key?(first, :ip)
      assert Map.has_key?(first, :hostname)
      assert Map.has_key?(first, :expiry)
      assert Map.has_key?(first, :client_id)
    end

    test "parses MAC addresses correctly" do
      devices = Devices.fetch_devices()
      macs = Enum.map(devices, & &1.mac)

      assert "b2:11:11:11:11:11" in macs
      assert "22:22:22:22:22:20" in macs
    end

    test "parses IP addresses correctly" do
      devices = Devices.fetch_devices()
      ips = Enum.map(devices, & &1.ip)

      assert "10.0.0.59" in ips
      assert "10.0.0.33" in ips
    end
  end
end

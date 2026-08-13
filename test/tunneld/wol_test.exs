defmodule Tunneld.WolTest do
  @moduledoc """
  A magic packet has exactly one correct shape, and getting it wrong fails the
  way everything else in this area fails: silently, with the machine simply not
  coming up. These pin the bytes.
  """
  use ExUnit.Case, async: true

  alias Tunneld.Wol

  @mac "58:47:ca:7c:52:5f"

  test "the magic packet is six 0xFF bytes then the MAC sixteen times" do
    packet = Wol.magic_packet(@mac)

    assert byte_size(packet) == 102
    assert binary_part(packet, 0, 6) == <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

    mac_bytes = <<0x58, 0x47, 0xCA, 0x7C, 0x52, 0x5F>>
    assert binary_part(packet, 6, 96) == :binary.copy(mac_bytes, 16)
  end

  test "case does not change the bytes" do
    assert Wol.magic_packet(@mac) == Wol.magic_packet(String.upcase(@mac))
  end

  test "only a colon-separated 48-bit MAC is accepted" do
    assert Wol.valid_mac?(@mac)
    assert Wol.valid_mac?(String.upcase(@mac))

    refute Wol.valid_mac?("58-47-ca-7c-52-5f")
    refute Wol.valid_mac?("58:47:ca:7c:52")
    refute Wol.valid_mac?("")
    refute Wol.valid_mac?("*")
    refute Wol.valid_mac?(nil)
  end

  test "a device with no usable MAC is refused rather than broadcast garbage" do
    assert {:error, :invalid_mac} = Wol.wake("not-a-mac")
    assert {:error, :invalid_mac} = Wol.wake(nil)
  end

  test "mock mode sends nothing" do
    # The suite runs with mock_data: true, so this is the laptop path.
    assert {:ok, ["mock"]} = Wol.wake(@mac)
  end

  test "targets always include the global broadcast, whatever the interface says" do
    assert {255, 255, 255, 255} in Wol.broadcast_targets()
  end

  # Regression: bind_to_device takes a binary and raises :badarg for anything
  # else, so an option mistake crashed the caller instead of falling back. The
  # socket path has to survive a refusal on any host.
  test "opening a socket never raises, whatever the interface is called" do
    prev = Application.get_env(:tunneld, :network)
    Application.put_env(:tunneld, :network, Keyword.put(prev || [], :downstream, "nope0"))
    on_exit(fn -> Application.put_env(:tunneld, :network, prev) end)

    # mock mode short-circuits wake/1, so exercise the real socket path directly
    assert {:ok, socket} = Wol.open_socket()
    :gen_udp.close(socket)
  end
end

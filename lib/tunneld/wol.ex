defmodule Tunneld.Wol do
  @moduledoc """
  Wake-on-LAN, sent by the gateway.

  A magic packet is six `0xFF` bytes followed by the target's MAC repeated
  sixteen times, delivered as a link-layer broadcast. It has to originate
  *inside* the target's broadcast domain, which is precisely why a WireGuard
  client cannot send one: a point-to-point L3 tunnel has no broadcast domain to
  put it in, and once the target is powered off there is no ARP entry to
  unicast to either. Both failures are silent, which is what makes this look
  like a configuration problem when it is a topology one.

  The gateway is on the wire, so the gateway sends it. Every device's MAC is
  already known from its DHCP lease, so nothing new is stored.

  Sending is not proof of waking: the packet is fire-and-forget, and whether
  the target acts on it depends on its NIC and firmware settings, which are not
  observable from here. `wake/1` reports that the packet went out, never that
  the machine came up.
  """

  require Logger

  # 9 is the conventional target (discard). Some firmware only listens on 7
  # (echo), and the packet is 102 bytes, so send both rather than make the
  # operator find out which one their NIC wants.
  @ports [9, 7]
  @mac_format ~r/^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$/

  @doc """
  Broadcast a magic packet for `mac` on the LAN interface.

  Returns `{:ok, targets}` naming the broadcast addresses it went to, or
  `{:error, reason}`.
  """
  @spec wake(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def wake(mac) when is_binary(mac) do
    mac = String.trim(mac)

    cond do
      not valid_mac?(mac) -> {:error, :invalid_mac}
      mock?() -> {:ok, ["mock"]}
      true -> broadcast(magic_packet(mac))
    end
  end

  def wake(_), do: {:error, :invalid_mac}

  @doc "True if the string is a colon-separated 48-bit MAC."
  def valid_mac?(mac) when is_binary(mac), do: Regex.match?(@mac_format, mac)
  def valid_mac?(_), do: false

  @doc """
  The magic packet for a MAC: `FF FF FF FF FF FF` then the six address bytes
  sixteen times over. 102 bytes, always.
  """
  @spec magic_packet(String.t()) :: binary()
  def magic_packet(mac) do
    bytes =
      mac
      |> String.split(":")
      |> Enum.map(&String.to_integer(&1, 16))
      |> :binary.list_to_bin()

    :binary.copy(<<0xFF>>, 6) <> :binary.copy(bytes, 16)
  end

  @doc """
  Broadcast addresses to aim at: the LAN interface's own broadcast address,
  read from the interface rather than assumed from a /24, plus the global
  broadcast as a fallback for a NIC that ignores the directed one.
  """
  def broadcast_targets do
    iface = to_charlist(Tunneld.Config.network(:downstream) || "eth1")

    from_iface =
      case :inet.getifaddrs() do
        {:ok, addrs} ->
          addrs
          |> Enum.find(fn {name, _opts} -> name == iface end)
          |> case do
            {_name, opts} -> Keyword.get_values(opts, :broadaddr)
            _ -> []
          end

        _ ->
          []
      end

    Enum.uniq(from_iface ++ [{255, 255, 255, 255}])
  end

  defp broadcast(packet) do
    case open_socket() do
      {:ok, socket} ->
        targets = broadcast_targets()

        try do
          for target <- targets, port <- @ports do
            case :gen_udp.send(socket, target, port, packet) do
              :ok ->
                :ok

              {:error, reason} ->
                Logger.warning(
                  "WoL send to #{:inet.ntoa(target)}:#{port} failed: #{inspect(reason)}"
                )
            end
          end

          {:ok, Enum.map(targets, &to_string(:inet.ntoa(&1)))}
        after
          :gen_udp.close(socket)
        end

      {:error, reason} ->
        {:error, {:socket_failed, reason}}
    end
  end

  # Bind to the LAN interface, because the global broadcast does not go where
  # you would assume: `ip route get 255.255.255.255` on the gateway resolves to
  # the *upstream* interface, so an unbound socket sends the target's MAC to the
  # ISP and nothing to the subnet the machine is actually on. Binding puts every
  # target on the downstream wire.
  #
  # SO_BINDTODEVICE needs privileges tunneld has on the gateway but may not have
  # elsewhere, so a refusal falls back to an unbound socket - the directed
  # broadcast (10.0.0.255) still routes correctly on its own.
  @doc false
  # `iface` is an argument rather than a config read so the fallback can be
  # exercised without mutating global application env - a test that did so
  # raced every other async test that reads the downstream interface.
  def open_socket(iface \\ nil) do
    iface = iface || Tunneld.Config.network(:downstream) || "eth1"
    base = [:binary, {:broadcast, true}, {:active, false}]

    # `bind_to_device` takes a BINARY interface name and rejects anything else
    # by raising :badarg out of :inet_udp.open/2 - it does not return an error
    # tuple - so the fallback has to catch an exit, not match on {:error, _}.
    # Getting this wrong turned a working unbound send into a crash.
    try do
      case :gen_udp.open(0, [{:bind_to_device, to_string(iface)} | base]) do
        {:ok, socket} -> {:ok, socket}
        {:error, reason} -> unbound_socket(iface, reason, base)
      end
    catch
      kind, reason -> unbound_socket(iface, {kind, reason}, base)
    end
  end

  defp unbound_socket(iface, reason, base) do
    Logger.warning("WoL could not bind to #{iface} (#{inspect(reason)}); sending unbound")
    :gen_udp.open(0, base)
  end

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)
end

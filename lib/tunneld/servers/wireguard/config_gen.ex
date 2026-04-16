defmodule Tunneld.Servers.Wireguard.ConfigGen do
  @moduledoc """
  Pure functions that render WireGuard configuration files.

  Generates:
  - Server-side `wg0.conf` for `wg syncconf`
  - Client-side `.conf` for peer devices (download or QR code)
  - QR-code-ready string of a peer `.conf`

  All functions are pure — no side effects, no CLI calls, no GenServer.
  """

  @doc """
  Render the server's wg0.conf for `wg syncconf`.

  Includes the server private key and all peers with their allowed IPs.
  This format is compatible with `wg syncconf wg0 <(wg-quick strip /path/to/wg0.conf)`.
  """
  def server_conf(state) do
    priv = state["private_key"]
    port = state["listen_port"]

    peer_lines =
      state["peers"]
      |> Map.values()
      |> Enum.map(fn peer ->
        "[Peer]\nPublicKey = #{peer["public_key"]}\nAllowedIPs = #{peer["ip"]}/32"
      end)
      |> Enum.join("\n")

    """
    [Interface]
    PrivateKey = #{priv}
    ListenPort = #{port}
    #{peer_lines}
    """
    |> String.trim_trailing()
  end

  @doc """
  Render a client-side `.conf` for a peer device.

  Requires the peer record (with `private_key` included — only available at
  creation or regeneration time) and the server state.

  For full-tunnel peers, `AllowedIPs` is set to `0.0.0.0/0` (all traffic).
  For split-tunnel peers, `AllowedIPs` is set to the server's subnet only.
  """
  def peer_conf(peer, state) do
    priv = peer["private_key"]
    address = "#{peer["ip"]}/24"
    dns = dns_server(state)
    public_key = state["public_key"]
    endpoint = "#{state["endpoint"]}:#{state["listen_port"]}"
    allowed_ips = allowed_ips(peer, state)

    """
    [Interface]
    PrivateKey = #{priv}
    Address = #{address}
    DNS = #{dns}

    [Peer]
    PublicKey = #{public_key}
    Endpoint = #{endpoint}
    AllowedIPs = #{allowed_ips}
    PersistentKeepalive = 25
    """
    |> String.trim_trailing()
  end

  @doc """
  Render a QR-code-ready string of a peer `.conf`.

  Returns the same content as `peer_conf/2` as a single string.
  QR encoding libraries expect a plain string input.
  """
  def peer_conf_qr(peer, state) do
    peer_conf(peer, state)
  end

  # --- Private Helpers ---

  defp allowed_ips(peer, state) do
    if peer["full_tunnel"] do
      "0.0.0.0/0"
    else
      state["subnet"]
    end
  end

  defp dns_server(state) do
    # Peers use the gateway's Ethernet IP as DNS server
    # This inherits the existing dnsmasq + dnscrypt stack
    gateway = Application.get_env(:tunneld, :network, [])[:gateway]

    if gateway do
      gateway
    else
      # Fallback: derive from subnet (server IP)
      subnet_to_server_ip(state["subnet"])
      |> String.replace(~r/\/\d+$/, "")
    end
  end

  defp subnet_to_server_ip(subnet) do
    [prefix, mask] = String.split(subnet, "/")
    [a, b, c, _d] = String.split(prefix, ".")
    "#{a}.#{b}.#{c}.1/#{mask}"
  end
end
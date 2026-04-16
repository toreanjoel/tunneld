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
    endpoint = format_endpoint(state["endpoint"], state["listen_port"])
    allowed_ips = allowed_ips(peer, state)
    name = peer["name"] || "peer"

    interface_lines = [
      "[Interface]",
      "# #{name}",
      "PrivateKey = #{priv}",
      "Address = #{address}",
      "DNS = #{dns}",
      "MTU = 1280",
      ""
    ]

    peer_lines =
      [
        "[Peer]",
        "PublicKey = #{public_key}",
        if(endpoint, do: "Endpoint = #{endpoint}"),
        "AllowedIPs = #{allowed_ips}",
        "PersistentKeepalive = 25"
      ]
      |> Enum.filter(& &1)

    Enum.join(interface_lines ++ peer_lines, "\n")
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
      # Split tunnel: VPN subnet + LAN subnet so peers can reach
      # other devices on the local network (SSH, dashboard, etc.)
      gateway_subnet = gateway_subnet()
      "#{state["subnet"]}, #{gateway_subnet}"
    end
  end

  defp gateway_subnet do
    gateway = Application.get_env(:tunneld, :network, [])[:gateway]

    if gateway do
      # e.g. "10.0.0.1" → "10.0.0.0/24"
      [a, b, c, _d] = String.split(gateway, ".")
      "#{a}.#{b}.#{c}.0/24"
    else
      # Fallback — can't determine LAN subnet, only route VPN subnet
      nil
    end
  end

  defp dns_server(state) do
    # Use the VPN server's IP (x.x.x.1) as DNS for peers.
    # This is on the VPN subnet so both split-tunnel and
    # full-tunnel peers can reach it. dnsmasq listens on
    # all interfaces including wg0.
    subnet_to_server_ip(state["subnet"])
    |> String.replace(~r/\/\d+$/, "")
  end

  defp subnet_to_server_ip(subnet) do
    [prefix, mask] = String.split(subnet, "/")
    [a, b, c, _d] = String.split(prefix, ".")
    "#{a}.#{b}.#{c}.1/#{mask}"
  end

  defp format_endpoint(nil, _port), do: nil
  defp format_endpoint(endpoint, port) when is_binary(endpoint) do
    cond do
      # Already has brackets — assume port included (e.g. [::1]:51820)
      String.contains?(endpoint, "[") ->
        endpoint

      # Bare IPv6 address — wrap in brackets and add port
      String.contains?(endpoint, ":") and not String.contains?(endpoint, ".") ->
        "[#{endpoint}]:#{port}"

      # IPv4 or hostname with :port already
      String.contains?(endpoint, ":") ->
        endpoint

      # IPv4 or hostname — add port
      true ->
        "#{endpoint}:#{port}"
    end
  end
end
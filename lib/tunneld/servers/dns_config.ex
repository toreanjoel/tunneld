defmodule Tunneld.Servers.DnsConfig do
  @moduledoc """
  DNS server configuration persistence.

  Stores the upstream DNS server IP that dnsmasq forwards all queries to.
  Reads/writes `dns.json` via `Tunneld.Persistence`. Manages the dnsmasq
  drop-in config at `/etc/dnsmasq.d/tunneld_dns.conf`.
  """

  use GenServer

  @default_dns "1.1.1.1"
  @dnsmasq_conf "/etc/dnsmasq.d/tunneld_dns.conf"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    server = read_dns_server()

    unless Application.get_env(:tunneld, :mock_data, false) do
      write_dnsmasq_config(server)
      write_lan_domain_config()
      Tunneld.Servers.Services.restart_service(:dnsmasq, :no_notify)
    end

    {:ok, %{"server" => server}}
  end

  @doc "Returns the current DNS server IP."
  def get_dns_server do
    case Process.whereis(__MODULE__) do
      nil ->
        # GenServer hasn't started yet (e.g. called from Application.start/2
        # before the supervisor brings children up). Fall back to the
        # persisted value, or the hardcoded default if disk read fails.
        read_dns_server()

      _pid ->
        try do
          GenServer.call(__MODULE__, :get_dns_server)
        catch
          :exit, _ -> read_dns_server()
        end
    end
  end

  @doc "Sets a new DNS server IP, persists it, updates iptables and dnsmasq."
  def set_dns_server(ip) when is_binary(ip) do
    GenServer.call(__MODULE__, {:set_dns_server, ip})
  end

  @impl true
  def handle_call(:get_dns_server, _from, state) do
    {:reply, state["server"] || @default_dns, state}
  end

  @impl true
  def handle_call(:ensure_lan_domain, _from, state) do
    unless Application.get_env(:tunneld, :mock_data, false) do
      write_lan_domain_config()
      Tunneld.Servers.Services.restart_service(:dnsmasq, :no_notify)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:set_dns_server, ip}, _from, _state) do
    path = dns_path()
    Tunneld.Persistence.write_json(path, %{"server" => ip})

    unless Application.get_env(:tunneld, :mock_data, false) do
      Tunneld.Iptables.set_dns_server(ip)
      write_dnsmasq_config(ip)
      Tunneld.Servers.Services.restart_service(:dnsmasq, :no_notify)
    end

    Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:details", %{
      id: "sidebar_details",
      module: TunneldWeb.Live.Components.Sidebar.Details,
      data: %{dns_server: ip}
    })

    {:reply, :ok, %{"server" => ip}}
  end

  @doc """
  Ensure the LAN domain (`*.tunneld.lan`) resolves to the gateway IP so named
  resources and exposed services are reachable by name across the subnet.
  No-op in mock mode.
  """
  def ensure_lan_domain do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :ensure_lan_domain)
    else
      unless Application.get_env(:tunneld, :mock_data, false) do
        write_lan_domain_config()
        Tunneld.Servers.Services.restart_service(:dnsmasq, :no_notify)
      end

      :ok
    end
  end

  defp write_dnsmasq_config(server) do
    File.write!(@dnsmasq_conf, "server=#{server}\n")
  end

  @lan_domain_conf "/etc/dnsmasq.d/tunneld_resources.conf"

  # Resolve any *.tunneld.lan name to the gateway so named resources and
  # exposed container services are reachable across the subnet.
  defp write_lan_domain_config do
    gateway = gateway_ip()
    File.write!(@lan_domain_conf, "address=/.tunneld.lan/#{gateway}\n")
  end

  defp gateway_ip do
    case Application.get_env(:tunneld, :network, []) do
      kw when is_list(kw) -> Keyword.get(kw, :gateway)
      map when is_map(map) -> Map.get(map, :gateway) || Map.get(map, "gateway")
      _ -> nil
    end
  end

  defp read_dns_server do
    path = dns_path()

    case Tunneld.Persistence.read_json(path) do
      {:ok, %{"server" => server}} when is_binary(server) and server != "" -> server
      _ -> @default_dns
    end
  end

  defp dns_path do
    Path.join(Tunneld.Config.fs_root(), Tunneld.Config.fs(:dns) || "dns.json")
  end
end

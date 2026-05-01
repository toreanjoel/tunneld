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
    ensure_dnsmasq_config(server)
    {:ok, %{"server" => server}}
  end

  @doc "Returns the current DNS server IP."
  def get_dns_server do
    try do
      GenServer.call(__MODULE__, :get_dns_server)
    rescue
      _ -> @default_dns
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

  defp ensure_dnsmasq_config(server) do
    mock? = Application.get_env(:tunneld, :mock_data, false)
    unless mock? do
      write_dnsmasq_config(server)
      Tunneld.Servers.Services.restart_service(:dnsmasq, :no_notify)
    end
  end

  defp write_dnsmasq_config(server) do
    File.write!(@dnsmasq_conf, "server=#{server}\n")
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

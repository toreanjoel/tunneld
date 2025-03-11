defmodule Sentinel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Sentinel.Servers.FakeData.Whitelist
  alias Sentinel.Servers.{Auth, Session, Services, Logs, Devices, Blacklist, Whitelist, Resources, Wlan}

  @impl true
  def start(_type, _args) do
    IO.inspect("MAKE SURE TO SET THE MOCK_DATA ENV VAR for development")
    IO.inspect("MAKE SURE THE OS IS USING LEGACY IPTABLES: sudo update-alternatives --set iptables /usr/sbin/iptables-legacy")

    children = [
      SentinelWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:sentinel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sentinel.PubSub},
      # Start a worker by calling: Sentinel.Worker.start_link(arg)
      # {Sentinel.Worker, arg},
      # Start to serve requests, typically the last entry
      SentinelWeb.Endpoint,
      {Resources, []},
      {Services, []},
      {Logs, []},
      {Devices, []},
      {Auth, []},
      {Blacklist, []},
      {Whitelist, []},
      {Session, []},
      {Wlan, []}
    ]

    # This should not be async, we want this to complete before any other servers init data
    # This will prevent race conditions
    if not Application.get_env(:sentinel, :mock_data, false) do
      Task.start(fn ->
        bridge_interfaces()
      end)
      Iptables.reset()
    end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sentinel.Supervisor]

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SentinelWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  #
  # Setup the basic bridge setup on startup in order to link the wlan and eth interfaces
  # This is used in order to get the linking of interfaces and we need to make these variables
  #
  def bridge_interfaces do
    commands = [
      "ip link add name br0 type bridge",
      "ip link set eth0 master br0",
      "ip link set wlan0 master br0",
      "ip link set eth0 up",
      "ip link set wlan0 up",
      "ip link set br0 up"
    ]

    Enum.each(commands, fn cmd ->
      case System.cmd("sudo", String.split(cmd, " ")) do
        {output, 0} -> IO.puts("Success: #{cmd}\n#{output}")
        {error_msg, exit_code} -> IO.puts("Error (#{exit_code}): #{cmd}\n#{error_msg}")
      end
    end)

    Sentinel.Servers.Services.restart_service(:dhcpcd)
  end
end

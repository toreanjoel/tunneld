defmodule Tunneld.Application do
  @moduledoc """
  OTP Application entry point. Starts the supervision tree with all
  GenServers, PubSub, and the Phoenix endpoint. In production, also
  resets iptables firewall rules on startup.

  Supervision tree (after WireGuard mesh removal):
    Session, SystemResources, Services, Resources, Devices, Auth,
    DnsConfig, Updater, Geolocation, Endpoint.
  """

  use Application

  alias Tunneld.Servers.{
    Auth,
    Session,
    Services,
    Devices,
    SystemResources,
    Resources,
    DnsConfig,
    Updater
  }

  alias Tunneld.Machines

  @impl true
  def start(_type, _args) do
    Tunneld.Template.ensure_template()

    children =
      [
        TunneldWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:tunneld, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Tunneld.PubSub}
      ] ++
        mock_children() ++
        [
          {Session, []},
          {SystemResources, []},
          {Services, []},
          {Resources, []},
          {Devices, []},
          {Auth, []},
          {DnsConfig, []},
          {Updater, []},
          {Machines, []},
          {Tunneld.AgentTokens, []},
          {Tunneld.Jobs, []},
          {Tunneld.Geolocation, []},
          TunneldWeb.Endpoint
        ]

    if not Application.get_env(:tunneld, :mock_data, false) do
      Tunneld.Iptables.reset()
    end

    opts = [strategy: :one_for_one, name: Tunneld.Supervisor]

    Supervisor.start_link(children, opts)
  end

  defp mock_children do
    if Application.get_env(:tunneld, :mock_data, false) do
      [{Tunneld.Machines.SSH.Mock.MockState, []}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TunneldWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

defmodule Tunneld.Application do
  @moduledoc """
  OTP Application entry point. Starts the supervision tree with all
  GenServers, PubSub, and the Phoenix endpoint. In production, also
  resets iptables firewall rules on startup.
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

  @impl true
  def start(_type, _args) do
    Tunneld.Template.ensure_template()

    children =
      [
        TunneldWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:tunneld, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Tunneld.PubSub}
      ] ++
        [
          {Session, []},
          {SystemResources, []},
          {Services, []},
          {Resources, []},
          {Devices, []},
          {Auth, []},
          {DnsConfig, []},
          {Updater, []},
          {Tunneld.AgentTokens, []},
          {Tunneld.Jobs, []},
          {Tunneld.Geolocation, []},
          TunneldWeb.Endpoint
        ]

    if not Application.get_env(:tunneld, :mock_data, false) do
      Tunneld.Iptables.reset()
      # reset/0 flushes, so anything granted at runtime has to be re-asserted
      # here or it is lost on every restart.
      Tunneld.Clients.ensure_lan_rules()
    end

    opts = [strategy: :one_for_one, name: Tunneld.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Machines is a plain module, so boot-time recovery has no init/1 to run
        # from. Probing the fleet can take a minute per unreachable host, so it
        # must not block application start. Only run it once the tree is up.
        Task.start(fn -> Tunneld.Machines.recover_all() end)
        {:ok, pid}

      other ->
        other
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

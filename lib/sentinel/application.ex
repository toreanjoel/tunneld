defmodule Sentinel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Sentinel.Servers.FakeData.Whitelist

  alias Sentinel.Servers.{
    Auth,
    Session,
    Services,
    Devices,
    Whitelist,
    Resources,
    Wlan,
    Cloudflare,
    Nodes
  }

  @impl true
  def start(_type, _args) do
    IO.inspect("MAKE SURE TO SET THE MOCK_DATA ENV VAR for development")

    IO.inspect(
      "MAKE SURE THE OS IS USING LEGACY IPTABLES: sudo update-alternatives --set iptables /usr/sbin/iptables-legacy"
    )

    children = [
      SentinelWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:sentinel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sentinel.PubSub},
      # Start a worker by calling: Sentinel.Worker.start_link(arg)
      # {Sentinel.Worker, arg},
      # Start to serve requests, typically the last entry
      SentinelWeb.Endpoint,
      {Wlan, []},
      {Cloudflare, []},
      {Session, []},
      {Resources, []},
      {Services, []},
      {Nodes, []},
      {Devices, []},
      {Auth, []},
      {Whitelist, []}
    ]

    # This should not be async, we want this to complete before any other servers init data
    # This will prevent race conditions
    if not Application.get_env(:sentinel, :mock_data, false) do
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
end

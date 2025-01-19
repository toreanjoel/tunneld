defmodule Sentinel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Sentinel.Servers.{Auth, Session, Services, Logs, Devices, Blacklist}

  @impl true
  def start(_type, _args) do
    IO.inspect("MAKE SURE TO SET THE MOCK_DATA ENV VAR for development")

    children = [
      SentinelWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:sentinel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sentinel.PubSub},
      # Start a worker by calling: Sentinel.Worker.start_link(arg)
      # {Sentinel.Worker, arg},
      # Start to serve requests, typically the last entry
      SentinelWeb.Endpoint,
      {Services, []},
      {Logs, []},
      {Devices, []},
      {Auth, []},
      {Blacklist, []},
      {Session, []}
    ]

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

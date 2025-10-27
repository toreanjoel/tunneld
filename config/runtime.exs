import Config

if System.get_env("PHX_SERVER") do
  config :tunneld, TunneldWeb.Endpoint, server: true
end

if System.get_env("MOCK_DATA") do
  config :tunneld, mock_data: true
end

# Only require these in PROD
if config_env() == :prod do
  # Required network envs (prod only)
  gateway = System.get_env("GATEWAY") || raise "Missing ENV: GATEWAY"
  wlan = System.get_env("WIFI_INTERFACE") || raise "Missing ENV: WIFI_INTERFACE"
  lan = System.get_env("LAN_INTERFACE") || raise "Missing ENV: LAN_INTERFACE"

  config :tunneld, :network,
    gateway: gateway,
    wlan: wlan,
    eth: lan,
    mullvad: System.get_env("MULLVAD_INTERFACE", "")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "ENV SECRET_KEY_BASE is missing. Generate with: mix phx.gen.secret"

  host = System.get_env("PHX_HOST", "localhost")
  port = String.to_integer(System.getenv("PORT") || "80")

  config :tunneld, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  gateway_origin = System.get_env("GATEWAY", "")
  hostname = System.get_env("HOSTNAME", "")
  check_origins = ["http://#{gateway_origin}", "http://localhost", "http://#{hostname}"]

  config :tunneld, TunneldWeb.Endpoint,
    url: [host: host, port: 80, scheme: "http"],
    http: [ip: {0, 0, 0, 0}, port: port],
    check_origin: check_origins,
    secret_key_base: secret_key_base

  # Prod data paths (overrideable via ENV)
  config :tunneld, :fs,
    root: System.get_env("TUNNELD_DATA", "/var/lib/tunneld"),
    auth: System.get_env("TUNNELD_AUTH_FILE", "auth.json"),
    shares: System.get_env("TUNNELD_SHARES_FILE", "shares.json")

  config :tunneld, :config_dir, path: System.get_env("TUNNELD_CONFIG", "/etc/tunneld")
end

import Config

if System.get_env("PHX_SERVER") do
  config :tunneld, TunneldWeb.Endpoint, server: true
end

mock_data? = System.get_env("MOCK_DATA") != nil

if mock_data? do
  config :tunneld, mock_data: true
end

# Data paths (overrideable via ENV)
default_root = if mock_data?, do: "data", else: "/var/lib/tunneld"
config :tunneld, :fs,
  root: System.get_env("TUNNELD_DATA", default_root),
  auth: System.get_env("TUNNELD_AUTH_FILE", "auth.json"),
  resources: System.get_env("TUNNELD_SHARES_FILE", "resources.json"),
  sqm: System.get_env("TUNNELD_SQM_FILE", "sqm.json"),
  dns_file: System.get_env("TUNNELD_DNS_FILE", "/etc/dnsmasq.d/tunneld_resources.conf")

config :tunneld, :certs,
  cert_dir: System.get_env("TUNNELD_CERT_DIR", "/etc/nginx/certs"),
  ca_dir: System.get_env("TUNNELD_CA_DIR", "/etc/tunneld/ca"),
  ca_file: "rootCA.key"

# Only require these in PROD
if config_env() == :prod do
  # Required network envs (prod only)
  gateway = System.get_env("GATEWAY") || raise "Missing ENV: GATEWAY"
  wlan = System.get_env("WIFI_INTERFACE") || raise "Missing ENV: WIFI_INTERFACE"
  lan = System.get_env("LAN_INTERFACE") || raise "Missing ENV: LAN_INTERFACE"
  device_id = System.get_env("DEVICE_ID") || raise "Missing ENV: DEVICE_ID"

  wifi_country = System.get_env("WIFI_COUNTRY")
  config :tunneld, :metadata,
    device_id: device_id

  config :tunneld, :network,
    gateway: gateway,
    wlan: wlan,
    eth: lan,
    mullvad: System.get_env("MULLVAD_INTERFACE", ""),
    country: wifi_country

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "ENV SECRET_KEY_BASE is missing. Generate with: mix phx.gen.secret"

  host = System.get_env("PHX_HOST", "localhost")
  port = String.to_integer(System.get_env("PORT") || "80")

  config :tunneld, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  gateway_origin = System.get_env("GATEWAY", "")
  hostname = System.get_env("HOSTNAME", "")
  check_origins = ["http://#{gateway_origin}", "http://localhost", "http://#{hostname}", "http://tunneld.local", "https://tunneld.local"]

  config :tunneld, TunneldWeb.Endpoint,
    url: [host: host, port: 80, scheme: "http"],
    http: [ip: {0, 0, 0, 0}, port: port],
    check_origin: check_origins,
    secret_key_base: secret_key_base,
    server: true

  config :tunneld, :config_dir, path: System.get_env("TUNNELD_CONFIG", "/etc/tunneld")
  config :tunneld, :build_dir, path: System.get_env("TUNNELD_BUILD", "/opt/tunneld")
end

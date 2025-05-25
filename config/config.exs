# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sentinel,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :sentinel, SentinelWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SentinelWeb.ErrorHTML, json: SentinelWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sentinel.PubSub,
  live_view: [signing_salt: "IT1chlHR"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  sentinel: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  sentinel: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# DEFAILT ADMIN DASHBOARD DETAILS
config :sentinel, :auth,
  user: "admin",
  pass: "!admin_123!",
  ttl: 900 # 15 minutes

config :sentinel, :fs,
  root: "/data",
  auth: "/auth.json",
  whitelist: "/whitelist.json",
  tunnels: "/cloudflare_tunnels.json",
  instances: "/nodes.json",
  notifications: "/notifications.json",
  encryption: "/encryption.json"

# TODO: This needs to come from env variables from runtime config
config :sentinel, :network,
  wlan: "wlx202351114745",
  eth: "end0",
  mullvad: "wg0-mullvad",
  gateway: "10.0.0.1"

# ttyd terminal session default port to handle the terminal session
config :sentinel, :ttyd,
  port: "7681"

config :sentinel, version: "0.1.9"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

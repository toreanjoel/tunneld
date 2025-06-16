import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tunneld, TunneldWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9qgEbV9vpL0KYgml27yPiLjbv4G4ar4oBR7un+hoAWAzygjHN6nFMUVSZ/KHvmMI",
  server: false

# In test we don't send emails.
config :tunneld, Tunneld.Mailer, adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

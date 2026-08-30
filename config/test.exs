import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "h252Yta8X8NyrGd0W+boV4IpGdPQOWEG5PARRDYBKQbgKM9VLGXrk0KV4iDH+vI7",
  server: false

# In test we don't send emails
config :my_app, MyApp.Mailer, adapter: Swoosh.Adapters.Test

# Resend: a fixed webhook secret for signature tests and a Req.Test plug so
# MyApp.Resend never reaches the network.
config :my_app,
  resend_api_key: "re_test_key",
  resend_webhook_secret: "whsec_" <> Base.encode64("test-webhook-secret")

config :my_app, MyApp.Resend, req_options: [plug: {Req.Test, MyApp.Resend}, retry: false]

# Consumers of the Receiving API go through a Mox mock (defined in test/support/mocks.ex).
config :my_app, :resend_client, MyApp.ResendMock

# Let the OS pick a free port for the private metrics listener.
config :my_app, :metrics_port, 0

# PhoenixTest drives the endpoint directly.
config :phoenix_test, :endpoint, MyAppWeb.Endpoint

# LiveDashboard's OS Data page is not used in test; skip the os_mon port
# programs so they do not print "Erlang has closed" when the VM halts.
config :os_mon, start_cpu_sup: false, start_memsup: false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

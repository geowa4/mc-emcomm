import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :mc_emcomm, McEmcomm.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: "mc_emcomm_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mc_emcomm, McEmcommWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "h252Yta8X8NyrGd0W+boV4IpGdPQOWEG5PARRDYBKQbgKM9VLGXrk0KV4iDH+vI7",
  server: false

# In test we don't send emails
config :mc_emcomm, McEmcomm.Mailer, adapter: Swoosh.Adapters.Test

# Resend: a fixed webhook secret for signature tests and a Req.Test plug so
# McEmcomm.Resend never reaches the network.
config :mc_emcomm,
  resend_api_key: "re_test_key",
  resend_webhook_secret: "whsec_" <> Base.encode64("test-webhook-secret")

config :mc_emcomm, McEmcomm.Resend, req_options: [plug: {Req.Test, McEmcomm.Resend}, retry: false]

# Consumers of the Receiving API go through a Mox mock (defined in test/support/mocks.ex).
config :mc_emcomm, :resend_client, McEmcomm.ResendMock

# Storage: ReqS3.presign_form/1 and presign_url/1 are always stubbed in tests (§18)
# via a Mox mock instead of reaching Tigris.
config :mc_emcomm, s3_bucket: "mc-emcomm-test"
config :mc_emcomm, :storage_client, McEmcomm.StorageMock

# Let the OS pick a free port for the private metrics listener.
config :mc_emcomm, :metrics_port, 0

# The periodic retention scrubber (§20) isn't started in test; its work is
# exercised directly via McEmcomm.Sightings.scrub_before/1.
config :mc_emcomm, :start_retention_scrubber, false

# PhoenixTest drives the endpoint directly.
config :phoenix_test, :endpoint, McEmcommWeb.Endpoint

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

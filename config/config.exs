# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mc_emcomm, :scopes,
  user: [
    default: true,
    module: McEmcomm.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: McEmcomm.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :mc_emcomm,
  ecto_repos: [McEmcomm.Repo],
  generators: [timestamp_type: :utc_datetime]

# PostGIS geometry columns (geography(Point,4326)) need the geo_postgis
# Postgrex extension registered on the connection type set.
config :mc_emcomm, McEmcomm.Repo, types: McEmcomm.PostgrexTypes

# Configure the endpoint
config :mc_emcomm, McEmcommWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: McEmcommWeb.ErrorHTML, json: McEmcommWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: McEmcomm.PubSub,
  live_view: [signing_salt: "HuHRlVnG"]

# Session and remember-me cookies are marked Secure only where the app is
# served over HTTPS; config/prod.exs turns this on. Dev and test serve plain
# HTTP on localhost, where a Secure cookie would never be stored.
config :mc_emcomm, :secure_cookies, false

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer.
#
# Production uses Resend through Swoosh's first-party adapter and the Req API
# client (the API key is read in config/runtime.exs). dev.exs overrides the
# adapter with Swoosh.Adapters.Local (browse sent mail at /dev/mailbox) and
# test.exs with Swoosh.Adapters.Test.
config :mc_emcomm, McEmcomm.Mailer, adapter: Swoosh.Adapters.Resend

# Sender address for account emails; overridden by MAIL_FROM in production.
config :mc_emcomm, mail_from: "contact@example.com"
config :swoosh, api_client: Swoosh.ApiClient.Req

# Inbound webhook verification (McEmcommWeb.Plugs.VerifyResendSignature). The
# value comes from the environment in config/runtime.exs; the default here only
# makes the key exist.
config :mc_emcomm, resend_webhook_secret: nil

# Prometheus metrics are served by a dedicated Bandit listener on a private
# port (see McEmcommWeb.MetricsEndpoint). PromEx's Cowboy-based metrics server
# and Grafana integration are disabled.
config :mc_emcomm, :metrics_port, 9091

config :mc_emcomm, McEmcomm.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# OpenTelemetry: the resource (service name + version) is built in
# config/runtime.exs, where the exporter is also selected (OTLP in prod when
# OTEL_EXPORTER_OTLP_ENDPOINT is set, otherwise none).
config :opentelemetry, traces_exporter: :none

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  mc_emcomm: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  mc_emcomm: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id, :span_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

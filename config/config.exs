# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :my_app, :scopes,
  user: [
    default: true,
    module: MyApp.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: MyApp.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :my_app,
  ecto_repos: [MyApp.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :my_app, MyAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MyApp.PubSub,
  live_view: [signing_salt: "HuHRlVnG"]

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
config :my_app, MyApp.Mailer, adapter: Swoosh.Adapters.Resend

# Sender address for account emails; overridden by MAIL_FROM in production.
config :my_app, mail_from: "contact@example.com"
config :swoosh, api_client: Swoosh.ApiClient.Req

# Resend Receiving API client (MyApp.Resend) and inbound webhook verification
# (MyAppWeb.Plugs.VerifyResendSignature). Both values come from the
# environment in config/runtime.exs; the defaults here only make the keys exist.
config :my_app, resend_api_key: nil, resend_webhook_secret: nil

# Prometheus metrics are served by a dedicated Bandit listener on a private
# port (see MyAppWeb.MetricsEndpoint). PromEx's Cowboy-based metrics server
# and Grafana integration are disabled.
config :my_app, :metrics_port, 9091

config :my_app, MyApp.PromEx,
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
  my_app: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  my_app: [
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

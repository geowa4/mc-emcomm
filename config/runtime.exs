import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Build identity
#
# GIT_SHA is baked into the release image by the Dockerfile (`--build-arg
# GIT_SHA=...`, see CONTRIBUTING.md § Deployment). It is served at
# /healthz/version and attached to every trace as service.version.
git_sha = System.get_env("GIT_SHA", "unknown")
config :my_app, git_sha: git_sha
config :opentelemetry, resource: %{service: %{name: "my_app", version: git_sha}}

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/my_app start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :my_app, MyAppWeb.Endpoint, server: true
end

config :my_app, MyAppWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :my_app, MyAppWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/my_app_web/router\.ex$"E,
        ~r"lib/my_app_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :my_app, MyApp.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :my_app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :my_app, MyAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :my_app, MyAppWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :my_app, MyAppWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Mailer, Resend and inbound webhooks
  #
  # RESEND_API_KEY feeds both the Swoosh adapter (outbound mail) and
  # MyApp.Resend, the Req-based Receiving API client used by the /inbox
  # LiveView. RESEND_WEBHOOK_SECRET verifies inbound webhook signatures.
  config :my_app, MyApp.Mailer, api_key: System.fetch_env!("RESEND_API_KEY")
  config :my_app, resend_api_key: System.fetch_env!("RESEND_API_KEY")
  # MAIL_FROM must be an address on a domain verified in Resend.
  config :my_app, mail_from: System.fetch_env!("MAIL_FROM")
  config :my_app, resend_webhook_secret: System.fetch_env!("RESEND_WEBHOOK_SECRET")

  # ## Metrics
  #
  # Private Prometheus listener; scraped by Fly over the private network.
  config :my_app, :metrics_port, String.to_integer(System.get_env("METRICS_PORT") || "9091")

  # ## OpenTelemetry
  #
  # The OTLP exporter reads OTEL_EXPORTER_OTLP_ENDPOINT / _HEADERS / _PROTOCOL
  # itself; we only turn tracing on when an endpoint is configured so a
  # deployment without a collector stays quiet.
  if System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
    config :opentelemetry, traces_exporter: :otlp
  end

  # ## Logging
  #
  # JSON logs with request and trace correlation ids.
  config :logger, :default_handler,
    formatter: {LoggerJSON.Formatters.Basic, metadata: [:request_id, :trace_id, :span_id]}
end

if config_env() == :dev do
  # Optional in dev: set RESEND_API_KEY / RESEND_WEBHOOK_SECRET to exercise the
  # /inbox LiveView and the webhook against a real Resend account. Outbound
  # mail stays on the local adapter regardless.
  config :my_app,
    resend_api_key: System.get_env("RESEND_API_KEY"),
    resend_webhook_secret:
      System.get_env("RESEND_WEBHOOK_SECRET", "whsec_" <> Base.encode64("dev-webhook-secret"))
end

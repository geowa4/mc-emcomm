defmodule MyApp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_opentelemetry()

    children = [
      MyApp.PromEx,
      MyAppWeb.Telemetry,
      MyApp.Repo,
      {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Task.Supervisor, name: MyApp.TaskSupervisor},
      MyApp.Health.Probe,
      # Start to serve requests, typically the last entry
      MyAppWeb.Endpoint,
      # Private Prometheus listener (never exposed as a public Fly service).
      {Bandit,
       plug: MyAppWeb.MetricsEndpoint, port: Application.fetch_env!(:my_app, :metrics_port)}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Attaches the OpenTelemetry telemetry handlers for Phoenix (including
  # LiveView), Bandit, and Ecto before the supervision tree starts so that
  # the first request is traced. The exporter is selected in config/runtime.exs.
  defp setup_opentelemetry do
    OpentelemetryPhoenix.setup(adapter: :bandit, liveview: true)
    OpentelemetryBandit.setup()
    OpentelemetryEcto.setup([:my_app, :repo])
  end
end

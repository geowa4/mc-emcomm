defmodule McEmcomm.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_opentelemetry()

    children =
      [
        McEmcomm.PromEx,
        McEmcommWeb.Telemetry,
        McEmcomm.Repo,
        {DNSCluster, query: Application.get_env(:mc_emcomm, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: McEmcomm.PubSub},
        {Task.Supervisor, name: McEmcomm.TaskSupervisor}
      ] ++
        probe_child() ++
        retention_scrubber_child() ++
        [
          # Start to serve requests, typically the last entry
          McEmcommWeb.Endpoint,
          # Private Prometheus listener (never exposed as a public Fly service).
          {Bandit,
           plug: McEmcommWeb.MetricsEndpoint,
           port: Application.fetch_env!(:mc_emcomm, :metrics_port)}
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: McEmcomm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    McEmcommWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Disabled in test (config/test.exs): the boot-time probe would query before
  # test_helper.exs flips the sandbox to :manual, and the flip then yanks its
  # in-flight connection. Tests that need the process start their own.
  defp probe_child do
    if Application.get_env(:mc_emcomm, :start_health_probe, true) do
      [McEmcomm.Health.Probe]
    else
      []
    end
  end

  # Disabled in test (config/test.exs) so the periodic scrub never races the
  # SQL sandbox from an unowned connection.
  defp retention_scrubber_child do
    if Application.get_env(:mc_emcomm, :start_retention_scrubber, true) do
      [McEmcomm.RetentionScrubber]
    else
      []
    end
  end

  # Attaches the OpenTelemetry telemetry handlers for Phoenix (including
  # LiveView), Bandit, and Ecto before the supervision tree starts so that
  # the first request is traced. The exporter is selected in config/runtime.exs.
  defp setup_opentelemetry do
    OpentelemetryPhoenix.setup(adapter: :bandit, liveview: true)
    OpentelemetryBandit.setup()
    OpentelemetryEcto.setup([:mc_emcomm, :repo])
  end
end

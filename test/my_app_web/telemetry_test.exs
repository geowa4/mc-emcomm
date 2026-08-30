defmodule MyAppWeb.TelemetryTest do
  use ExUnit.Case, async: true

  # NB: not aliased as `Telemetry`, which would shadow `Telemetry.Metrics`.
  alias MyAppWeb.Telemetry, as: AppTelemetry

  @metric_structs [
    Telemetry.Metrics.Counter,
    Telemetry.Metrics.Distribution,
    Telemetry.Metrics.LastValue,
    Telemetry.Metrics.Sum,
    Telemetry.Metrics.Summary
  ]

  # The list being non-empty is already proven by the compiler's type checker,
  # so these only assert what it cannot see.
  test "every metric definition is well formed" do
    for metric <- AppTelemetry.metrics() do
      assert metric.__struct__ in @metric_structs,
             "#{inspect(metric.name)} is not a Telemetry.Metrics definition"

      assert metric.event_name != [], "#{inspect(metric.name)} has no event name"
      assert is_list(metric.tags)
    end
  end

  test "the repo metrics use the repo's configured telemetry prefix" do
    prefix =
      Application.fetch_env!(:my_app, MyApp.Repo)[:telemetry_prefix] || [:my_app, :repo]

    assert Enum.any?(AppTelemetry.metrics(), &List.starts_with?(&1.event_name, prefix))
  end
end

defmodule McEmcomm.PromEx.MCPPluginTest do
  use ExUnit.Case, async: true

  alias McEmcomm.PromEx.MCPPlugin

  test "declares well-formed event metrics on the mcp telemetry events" do
    %PromEx.MetricTypes.Event{metrics: metrics} = MCPPlugin.event_metrics([])
    assert length(metrics) == 5

    for metric <- metrics do
      assert List.starts_with?(metric.event_name, [:mc_emcomm, :mcp])
      assert is_list(metric.tags)
    end
  end

  test "is registered with the app's PromEx module" do
    assert MCPPlugin in McEmcomm.PromEx.plugins()
  end
end

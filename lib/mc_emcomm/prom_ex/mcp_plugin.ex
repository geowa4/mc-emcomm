defmodule McEmcomm.PromEx.MCPPlugin do
  @moduledoc """
  Prometheus metrics for the MCP connector, built from the
  `[:mc_emcomm, :mcp, ...]` telemetry events the transport, tool registry,
  and OAuth endpoints emit (SPEC.md §28). Served with the rest of PromEx on
  the private metrics port.
  """
  use PromEx.Plugin

  @request_stop [:mc_emcomm, :mcp, :request, :stop]
  @tool_stop [:mc_emcomm, :mcp, :tool, :stop]
  @oauth [:mc_emcomm, :mcp, :oauth]

  @buckets [10, 50, 100, 250, 500, 1_000, 2_500, 5_000]

  @impl true
  def event_metrics(_opts) do
    Event.build(:mc_emcomm_mcp_event_metrics, [
      counter([:mc_emcomm, :mcp, :requests, :total],
        event_name: @request_stop,
        description: "MCP requests handled, by method and outcome.",
        tags: [:method, :outcome]
      ),
      distribution([:mc_emcomm, :mcp, :request, :duration, :milliseconds],
        event_name: @request_stop,
        measurement: :duration,
        description: "MCP request duration.",
        reporter_options: [buckets: @buckets],
        tags: [:method],
        unit: {:native, :millisecond}
      ),
      counter([:mc_emcomm, :mcp, :tool, :calls, :total],
        event_name: @tool_stop,
        description: "MCP tool calls, by tool and outcome.",
        tags: [:tool, :outcome]
      ),
      distribution([:mc_emcomm, :mcp, :tool, :duration, :milliseconds],
        event_name: @tool_stop,
        measurement: :duration,
        description: "MCP tool call duration.",
        reporter_options: [buckets: @buckets],
        tags: [:tool],
        unit: {:native, :millisecond}
      ),
      counter([:mc_emcomm, :mcp, :oauth, :operations, :total],
        event_name: @oauth,
        description:
          "OAuth operations (register, authorize, token, refresh, revoke), by outcome.",
        tags: [:operation, :outcome]
      )
    ])
  end
end

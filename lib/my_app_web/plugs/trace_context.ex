defmodule MyAppWeb.Plugs.TraceContext do
  @moduledoc """
  Copies the current OpenTelemetry trace and span ids into `Logger` metadata so
  JSON logs can be correlated with traces. The request span is started by
  `opentelemetry_bandit` before this plug runs.
  """
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        conn

      span_ctx ->
        Logger.metadata(
          trace_id: OpenTelemetry.Span.hex_trace_id(span_ctx),
          span_id: OpenTelemetry.Span.hex_span_id(span_ctx)
        )

        conn
    end
  end
end

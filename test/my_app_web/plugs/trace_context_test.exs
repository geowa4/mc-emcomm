defmodule MyAppWeb.Plugs.TraceContextTest do
  # Writes Logger metadata for the calling process.
  use ExUnit.Case, async: true

  import Plug.Test

  require OpenTelemetry.Tracer

  alias MyAppWeb.Plugs.TraceContext

  @opts TraceContext.init([])

  setup do
    Logger.metadata(trace_id: nil, span_id: nil)
    :ok
  end

  test "copies the active trace and span ids into Logger metadata" do
    OpenTelemetry.Tracer.with_span "request" do
      conn = :get |> conn("/") |> TraceContext.call(@opts)

      refute conn.halted

      metadata = Logger.metadata()
      assert is_binary(metadata[:trace_id])
      assert is_binary(metadata[:span_id])
      assert String.match?(metadata[:trace_id], ~r/\A[0-9a-f]{32}\z/)
      assert String.match?(metadata[:span_id], ~r/\A[0-9a-f]{16}\z/)
    end
  end

  test "passes the conn through untouched when there is no span" do
    conn = :get |> conn("/")

    assert TraceContext.call(conn, @opts) == conn
    refute Logger.metadata()[:trace_id]
  end
end

defmodule McEmcommWeb.MCP.Transport do
  @moduledoc """
  The Streamable HTTP transport at `/mcp`, MCP revision 2026-07-28 only
  (SPEC.md §28).

  Every request is one HTTP POST carrying exactly one JSON-RPC message and is
  fully described by its bearer token, headers, and body: there is no
  session, no server-side connection state, and no SSE — every response is a
  single JSON document. Notifications are acknowledged with 202. GET and
  DELETE, which earlier revisions used for the standalone stream and session
  teardown, answer 405. OPTIONS is the CORS preflight.

  Three methods exist: `server/discover`, `tools/list`, and `tools/call`.
  Anything else is `-32601` with HTTP 404. Protocol failures are JSON-RPC
  errors; tool failures are ordinary results with `isError: true`
  (`McEmcomm.MCP.Tools.Registry`).
  """
  @behaviour Plug

  import Plug.Conn

  require OpenTelemetry.Tracer, as: Tracer

  alias McEmcomm.MCP.Context
  alias McEmcomm.MCP.Protocol
  alias McEmcomm.MCP.Tools.Registry
  alias McEmcomm.OAuth
  alias McEmcommWeb.Plugs.MCPAuth

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "POST"} = conn, _opts), do: handle_post(conn)

  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts), do: send_resp(conn, 204, "")

  def call(conn, _opts) do
    conn
    |> put_resp_header("allow", "POST, OPTIONS")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(
      405,
      Jason.encode!(%{
        "error" => "method_not_allowed",
        "error_description" =>
          "This MCP endpoint speaks revision 2026-07-28: every message is a POST; " <>
            "there is no GET stream and no session to DELETE."
      })
    )
  end

  defp handle_post(conn) do
    conn = assign(conn, :mcp_started_at, System.monotonic_time())

    with :ok <- check_origin(conn),
         {:ok, term} <- body(conn) do
      dispatch(conn, Protocol.decode(term))
    else
      {:error, :forbidden_origin} ->
        send_json(
          conn,
          403,
          Protocol.error_response(nil, Protocol.invalid_request(), "Origin not allowed")
        )

      {:error, :parse} ->
        send_json(conn, 400, Protocol.error_response(nil, Protocol.parse_error(), "Parse error"))

      {:error, :not_json} ->
        send_json(
          conn,
          400,
          Protocol.error_response(
            nil,
            Protocol.invalid_request(),
            "Content-Type must be application/json"
          )
        )
    end
  end

  # Streamable HTTP §Security: an Origin header, when present, must be one we
  # trust (DNS-rebinding defense). Server-side clients send none.
  defp check_origin(conn) do
    case get_req_header(conn, "origin") do
      [] -> :ok
      [origin | _] -> if OAuth.allowed_origin?(origin), do: :ok, else: {:error, :forbidden_origin}
    end
  end

  defp body(%Plug.Conn{assigns: %{mcp_message: message}}), do: message
  defp body(_conn), do: {:error, :not_json}

  defp dispatch(conn, {:error, code, message, data}) do
    send_json(conn, Protocol.http_status(code), Protocol.error_response(nil, code, message, data))
  end

  # The core protocol defines no client notifications over HTTP; accept and
  # discard them (202, no body) rather than fail a well-meaning client.
  defp dispatch(conn, {:notification, method, _params}) do
    emit(conn, method, nil, :accepted)
    send_resp(conn, 202, "")
  end

  defp dispatch(conn, {:request, id, method, params}) do
    headers = request_headers(conn)

    case Protocol.validate_headers(headers, method, params) do
      :ok ->
        conn
        |> mirror_headers(method, params)
        |> handle(id, method, params)

      {:error, code, message, data} ->
        send_json(
          conn,
          Protocol.http_status(code),
          Protocol.error_response(id, code, message, data)
        )
    end
  end

  defp request_headers(conn) do
    conn.req_headers
    |> Enum.filter(fn {name, _} -> String.starts_with?(name, "mcp-") end)
    |> Enum.reverse()
    |> Map.new()
  end

  # The transport mirrors the request-metadata headers on the response so
  # intermediaries can correlate both directions.
  defp mirror_headers(conn, method, params) do
    conn = put_resp_header(conn, "mcp-method", method)

    case {method, params["name"]} do
      {"tools/call", name} when is_binary(name) -> put_resp_header(conn, "mcp-name", name)
      _ -> conn
    end
  end

  defp handle(conn, id, "server/discover", params) do
    emit(conn, "server/discover", nil, :ok)

    trace(conn, params, "server/discover", fn -> send_ok(conn, id, Protocol.discover_result()) end)
  end

  defp handle(conn, id, "tools/list", params) do
    trace(conn, params, "tools/list", fn ->
      case Registry.list(params["cursor"]) do
        {:ok, result} ->
          emit(conn, "tools/list", nil, :ok)
          send_ok(conn, id, Protocol.result(result))

        {:error, :invalid_cursor} ->
          emit(conn, "tools/list", nil, :error)
          send_error(conn, id, Protocol.invalid_params(), "Invalid params: unknown cursor")
      end
    end)
  end

  defp handle(conn, id, "tools/call", params) do
    %Context{} = context = conn.assigns.mcp_context
    context = %Context{context | client_info: Protocol.client_info(params)}
    name = params["name"]

    trace(conn, params, "tools/call", fn ->
      name
      |> Registry.call(params["arguments"], context)
      |> respond_tool_call(conn, id, name)
    end)
  end

  defp handle(conn, id, method, _params) do
    emit(conn, method, nil, :method_not_found)
    send_error(conn, id, Protocol.method_not_found(), "Method not found: #{method}")
  end

  defp respond_tool_call({:ok, result}, conn, id, name) do
    outcome = if result["isError"], do: :tool_error, else: :ok
    emit(conn, "tools/call", name, outcome)
    send_ok(conn, id, Protocol.result(result))
  end

  defp respond_tool_call({:error, :unknown_tool}, conn, id, name) do
    emit(conn, "tools/call", name, :error)
    send_error(conn, id, Protocol.invalid_params(), "Unknown tool: #{inspect(name)}")
  end

  defp respond_tool_call({:error, {:insufficient_scope, scope}}, conn, _id, name) do
    emit(conn, "tools/call", name, :insufficient_scope)
    MCPAuth.insufficient_scope(conn, scope)
  end

  # Wraps the work in an OpenTelemetry span parented on the trace context the
  # client put in `_meta` (traceparent/tracestate/baggage), falling back to
  # the request span Bandit opened.
  defp trace(conn, params, method, fun) do
    ctx =
      :otel_propagator_text_map.extract_to(
        OpenTelemetry.Ctx.get_current(),
        Protocol.trace_carrier(params)
      )

    info = Protocol.client_info(params)

    attributes = %{
      "mcp.method.name" => method,
      "mcp.protocol.version" => Protocol.protocol_version(),
      "mcp.client.name" => info.name || "",
      "mcp.client.version" => info.version || "",
      "enduser.id" => user_id(conn)
    }

    attributes =
      case params["name"] do
        name when is_binary(name) -> Map.put(attributes, "mcp.tool.name", name)
        _ -> attributes
      end

    Tracer.with_span ctx, "mcp.#{method}", %{attributes: attributes} do
      fun.()
    end
  end

  # One telemetry event per request, with what a dashboard needs and nothing
  # that could identify a token.
  defp emit(conn, method, tool, outcome) do
    :telemetry.execute(
      [:mc_emcomm, :mcp, :request, :stop],
      %{duration: elapsed(conn), count: 1},
      %{method: method, tool: tool, outcome: outcome, user_id: user_id(conn)}
    )
  end

  defp elapsed(%Plug.Conn{assigns: %{mcp_started_at: started}}),
    do: System.monotonic_time() - started

  defp elapsed(_conn), do: 0

  defp user_id(%Plug.Conn{assigns: %{mcp_context: %Context{scope: %{user: %{id: id}}}}}), do: id
  defp user_id(_conn), do: nil

  defp send_ok(conn, id, result), do: send_json(conn, 200, Protocol.response(id, result))

  defp send_error(conn, id, code, message) do
    send_json(conn, Protocol.http_status(code), Protocol.error_response(id, code, message))
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end

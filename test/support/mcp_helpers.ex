defmodule McEmcommWeb.MCPHelpers do
  @moduledoc """
  Builds MCP 2026-07-28 requests for `POST /mcp` in tests: the
  `MCP-Protocol-Version`, `Mcp-Method`, and `Mcp-Name` headers, the
  `_meta` block every request carries, and the bearer token.
  """

  import Phoenix.ConnTest
  import Plug.Conn

  alias McEmcomm.MCP.Protocol

  @endpoint McEmcommWeb.Endpoint

  @doc "The `_meta` every request must carry."
  def meta(overrides \\ %{}) do
    Map.merge(
      %{
        "io.modelcontextprotocol/protocolVersion" => Protocol.protocol_version(),
        "io.modelcontextprotocol/clientInfo" => %{"name" => "ExUnit", "version" => "1"},
        "io.modelcontextprotocol/clientCapabilities" => %{}
      },
      overrides
    )
  end

  @doc "A JSON-RPC request body for `method`."
  def request(method, params \\ %{}, id \\ 1) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => Map.put_new(params, "_meta", meta())
    }
  end

  @doc """
  Posts one MCP message. Options: `:token` (bearer), `:headers` (extra or
  overriding request headers as a map; a nil value drops the default header),
  `:raw` (send the string body as is).
  """
  def mcp_post(conn, body, opts \\ []) do
    method = if is_map(body), do: body["method"], else: nil
    name = if is_map(body), do: get_in(body, ["params", "name"]), else: nil

    defaults = %{
      "content-type" => "application/json",
      "accept" => "application/json, text/event-stream",
      "mcp-protocol-version" => Protocol.protocol_version(),
      "mcp-method" => method,
      "mcp-name" => name
    }

    headers =
      defaults
      |> Map.merge(Keyword.get(opts, :headers, %{}))
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    conn =
      Enum.reduce(headers, conn, fn {k, v}, conn -> put_req_header(conn, k, v) end)

    conn =
      case Keyword.get(opts, :token) do
        nil -> conn
        token -> put_req_header(conn, "authorization", "Bearer " <> token)
      end

    payload = if Keyword.get(opts, :raw), do: body, else: Jason.encode!(body)
    post(conn, "/mcp", payload)
  end

  @doc "Calls `server/discover`."
  def discover(conn, token), do: mcp_post(conn, request("server/discover"), token: token)

  @doc "Calls `tools/list`."
  def list_tools(conn, token, params \\ %{}),
    do: mcp_post(conn, request("tools/list", params), token: token)

  @doc "Calls `tools/call` for `name` with `arguments`."
  def call_tool(conn, token, name, arguments \\ %{}) do
    mcp_post(conn, request("tools/call", %{"name" => name, "arguments" => arguments}),
      token: token
    )
  end

  @doc "The JSON-RPC result of a 200 response."
  def result(conn), do: json_response(conn, 200)["result"]

  @doc "The `structuredContent` of a successful tool call."
  def structured(conn) do
    %{"isError" => false, "structuredContent" => structured} = result(conn)
    structured
  end

  @doc "The error text of a failed tool call (`isError: true`)."
  def tool_error(conn) do
    %{"isError" => true, "content" => [%{"type" => "text", "text" => text}]} = result(conn)
    text
  end
end

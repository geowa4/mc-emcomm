defmodule McEmcommWeb.Plugs.MCPCors do
  @moduledoc """
  CORS for the MCP endpoint and the OAuth endpoints, for browser-based
  clients such as the MCP Inspector. Only origins `McEmcomm.OAuth.allowed_origin?/1`
  accepts are echoed back — never a wildcard, and never with credentials.
  Preflight requests are answered by the routed `preflight` action; this plug
  only adds the headers.
  """
  @behaviour Plug

  import Plug.Conn

  @allow_headers "authorization, content-type, accept, mcp-protocol-version, mcp-method, mcp-name"
  @expose_headers "mcp-method, mcp-name, www-authenticate, retry-after"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_req_header(conn, "origin") do
      [origin] ->
        if McEmcomm.OAuth.allowed_origin?(origin) do
          conn
          |> put_resp_header("access-control-allow-origin", origin)
          |> put_resp_header("access-control-allow-methods", "POST, GET, OPTIONS")
          |> put_resp_header("access-control-allow-headers", @allow_headers)
          |> put_resp_header("access-control-expose-headers", @expose_headers)
          |> put_resp_header("access-control-max-age", "600")
          |> put_resp_header("vary", "origin")
        else
          conn
        end

      _no_origin ->
        conn
    end
  end
end

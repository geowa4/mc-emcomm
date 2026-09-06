defmodule McEmcommWeb.Plugs.MCPRateLimit do
  @moduledoc """
  Applies `McEmcomm.MCP.RateLimiter` to a request. `key: :ip` counts per
  client address (the OAuth endpoints, and `/mcp` before authentication);
  `key: :token` counts per bearer token once `McEmcommWeb.Plugs.MCPAuth` has
  resolved it. Over the limit answers 429 with `Retry-After`.
  """
  @behaviour Plug

  import Plug.Conn

  alias McEmcomm.MCP.RateLimiter
  alias McEmcomm.OAuth

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :key)

  @impl Plug
  def call(conn, key_kind) do
    case RateLimiter.check(key(conn, key_kind), OAuth.rate_limit()) do
      :ok ->
        conn

      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          Jason.encode!(%{
            "error" => "rate_limited",
            "error_description" => "Too many requests; retry after #{retry_after} seconds."
          })
        )
        |> halt()
    end
  end

  defp key(%Plug.Conn{assigns: %{mcp_context: %{token_id: token_id}}}, :token),
    do: {:token, token_id}

  defp key(conn, _ip) do
    # Fly terminates TLS and forwards the visitor's address in Fly-Client-IP;
    # conn.remote_ip is the proxy otherwise (mirrors McEmcommWeb.Plugs.RecordSighting).
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] -> {:ip, ip}
      [] -> {:ip, conn.remote_ip}
    end
  end
end

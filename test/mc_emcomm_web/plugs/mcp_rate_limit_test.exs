defmodule McEmcommWeb.Plugs.MCPRateLimitTest do
  # Sync: lowers the shared per-minute limit and clears the shared ETS table.
  use McEmcommWeb.ConnCase, async: false

  alias McEmcomm.MCP.RateLimiter

  setup do
    original = Application.fetch_env!(:mc_emcomm, :mcp)
    Application.put_env(:mc_emcomm, :mcp, Keyword.put(original, :rate_limit, 2))
    RateLimiter.reset()

    on_exit(fn ->
      Application.put_env(:mc_emcomm, :mcp, original)
      RateLimiter.reset()
    end)

    :ok
  end

  test "the OAuth endpoints answer 429 with Retry-After once the per-IP limit is hit", %{
    conn: conn
  } do
    for _ <- 1..2 do
      assert conn |> get(~p"/.well-known/oauth-authorization-server") |> json_response(200)
    end

    conn = get(conn, ~p"/.well-known/oauth-authorization-server")
    assert %{"error" => "rate_limited"} = json_response(conn, 429)
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) in 1..60
  end

  test "a different client address has its own budget", %{conn: conn} do
    for _ <- 1..2, do: get(conn, ~p"/.well-known/oauth-authorization-server")
    assert conn |> get(~p"/.well-known/oauth-authorization-server") |> json_response(429)

    other = put_req_header(conn, "fly-client-ip", "203.0.113.9")
    assert other |> get(~p"/.well-known/oauth-authorization-server") |> json_response(200)
  end
end

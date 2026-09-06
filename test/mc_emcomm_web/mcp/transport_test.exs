defmodule McEmcommWeb.MCP.TransportTest do
  use McEmcommWeb.ConnCase, async: true

  import McEmcommWeb.MCPHelpers

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.MCP.Protocol
  alias McEmcomm.MCP.Tools.Registry
  alias McEmcomm.OAuth
  alias McEmcomm.OAuthFixtures

  setup do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2MCP"})
    %{member: member, token: OAuthFixtures.access_token_fixture(member.user)}
  end

  describe "authentication" do
    test "no token is 401 with a WWW-Authenticate challenge naming the resource metadata", %{
      conn: conn
    } do
      conn = mcp_post(conn, request("server/discover"))
      assert json_response(conn, 401)["error"] == "unauthorized"
      assert [challenge] = get_resp_header(conn, "www-authenticate")

      assert challenge =~
               ~s(Bearer resource_metadata="#{OAuth.issuer()}/.well-known/oauth-protected-resource")
    end

    test "an unknown, expired-looking, or wrong-audience token is 401 invalid_token", %{
      conn: conn,
      member: member
    } do
      conn1 = mcp_post(conn, request("server/discover"), token: "nope")
      assert json_response(conn1, 401)["error"] == "invalid_token"
      assert [challenge] = get_resp_header(conn1, "www-authenticate")
      assert challenge =~ ~s(error="invalid_token")

      wrong_audience =
        OAuthFixtures.access_token_fixture(member.user, audience: "https://other.example/mcp")

      assert mcp_post(conn, request("server/discover"), token: wrong_audience)
             |> json_response(401)

      refresh = OAuthFixtures.tokens_fixture(member.user).refresh_token
      assert mcp_post(conn, request("server/discover"), token: refresh) |> json_response(401)
    end

    test "a bearer token is never placed in the response", %{conn: conn, token: token} do
      conn = discover(conn, token)
      refute response(conn, 200) =~ token
    end
  end

  describe "server/discover" do
    test "returns the supported versions, capabilities, and serverInfo in _meta", %{
      conn: conn,
      token: token
    } do
      conn = discover(conn, token)
      result = result(conn)

      assert result["resultType"] == "complete"
      assert result["supportedVersions"] == ["2026-07-28"]
      assert result["capabilities"] == %{"tools" => %{}}
      assert is_binary(result["instructions"])
      assert result["ttlMs"] == 3_600_000
      assert result["cacheScope"] == "public"

      assert %{"name" => "mc_emcomm", "version" => _} =
               result["_meta"]["io.modelcontextprotocol/serverInfo"]

      assert get_resp_header(conn, "mcp-method") == ["server/discover"]
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "header validation" do
    test "a missing MCP-Protocol-Version is 400 -32022 listing the supported versions", %{
      conn: conn,
      token: token
    } do
      conn =
        mcp_post(conn, request("server/discover"),
          token: token,
          headers: %{"mcp-protocol-version" => nil}
        )

      body = json_response(conn, 400)
      assert body["id"] == 1
      assert body["error"]["code"] == -32_022
      assert body["error"]["data"]["supportedVersions"] == ["2026-07-28"]
      assert body["error"]["data"]["supported"] == ["2026-07-28"]
    end

    test "a legacy protocol version is 400 -32022", %{conn: conn, token: token} do
      body =
        conn
        |> mcp_post(request("server/discover"),
          token: token,
          headers: %{"mcp-protocol-version" => "2025-11-25"}
        )
        |> json_response(400)

      assert body["error"]["code"] == -32_022
      assert body["error"]["data"]["requested"] == "2025-11-25"
    end

    test "a _meta protocol version that disagrees with the header is 400 -32020", %{
      conn: conn,
      token: token
    } do
      body =
        request("server/discover", %{
          "_meta" => meta(%{"io.modelcontextprotocol/protocolVersion" => "2025-11-25"})
        })

      assert %{"error" => %{"code" => -32_020}} =
               conn |> mcp_post(body, token: token) |> json_response(400)
    end

    test "a request without _meta protocol version is 400 -32602", %{conn: conn, token: token} do
      body = %{"jsonrpc" => "2.0", "id" => 7, "method" => "server/discover", "params" => %{}}

      assert %{"id" => 7, "error" => %{"code" => -32_602}} =
               conn |> mcp_post(body, token: token) |> json_response(400)
    end

    test "a missing or mismatched Mcp-Method is 400 -32020", %{conn: conn, token: token} do
      assert %{"error" => %{"code" => -32_020}} =
               conn
               |> mcp_post(request("server/discover"),
                 token: token,
                 headers: %{"mcp-method" => nil}
               )
               |> json_response(400)

      assert %{"error" => %{"code" => -32_020}} =
               conn
               |> mcp_post(request("server/discover"),
                 token: token,
                 headers: %{"mcp-method" => "tools/list"}
               )
               |> json_response(400)
    end

    test "a missing or mismatched Mcp-Name on tools/call is 400 -32020", %{
      conn: conn,
      token: token
    } do
      body = request("tools/call", %{"name" => "list_active_nets", "arguments" => %{}})

      assert %{"error" => %{"code" => -32_020}} =
               conn
               |> mcp_post(body, token: token, headers: %{"mcp-name" => nil})
               |> json_response(400)

      assert %{"error" => %{"code" => -32_020}} =
               conn
               |> mcp_post(body, token: token, headers: %{"mcp-name" => "end_net"})
               |> json_response(400)
    end

    test "Mcp-Method and Mcp-Name are mirrored on the response", %{conn: conn, token: token} do
      conn = call_tool(conn, token, "list_active_nets")
      assert get_resp_header(conn, "mcp-method") == ["tools/call"]
      assert get_resp_header(conn, "mcp-name") == ["list_active_nets"]
    end
  end

  describe "envelope" do
    test "a notification is 202 with no body and needs no metadata headers", %{
      conn: conn,
      token: token
    } do
      body = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

      conn =
        mcp_post(conn, body,
          token: token,
          headers: %{"mcp-method" => nil, "mcp-protocol-version" => nil}
        )

      assert response(conn, 202) == ""
    end

    test "an unknown method is 404 -32601", %{conn: conn, token: token} do
      body = conn |> mcp_post(request("initialize"), token: token) |> json_response(404)
      assert body["error"]["code"] == -32_601
      assert body["error"]["message"] =~ "initialize"
    end

    test "malformed JSON is 400 -32700 with a null id", %{conn: conn, token: token} do
      body =
        conn
        |> mcp_post("{not json", token: token, raw: true, headers: %{"mcp-method" => "x"})
        |> json_response(400)

      assert body == %{
               "jsonrpc" => "2.0",
               "id" => nil,
               "error" => %{"code" => -32_700, "message" => "Parse error"}
             }
    end

    test "batches and JSON-RPC responses are 400 -32600", %{conn: conn, token: token} do
      assert %{"error" => %{"code" => -32_600}} =
               conn
               |> mcp_post([request("server/discover")],
                 token: token,
                 headers: %{"mcp-method" => "x"}
               )
               |> json_response(400)

      assert %{"error" => %{"code" => -32_600}} =
               conn
               |> mcp_post(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}},
                 token: token,
                 headers: %{"mcp-method" => "x"}
               )
               |> json_response(400)
    end

    test "a non-JSON content type is 400 -32600", %{conn: conn, token: token} do
      conn =
        mcp_post(conn, "hello",
          token: token,
          raw: true,
          headers: %{"content-type" => "text/plain", "mcp-method" => "x"}
        )

      assert %{"error" => %{"code" => -32_600}} = json_response(conn, 400)
    end

    test "invalid tools/call params are protocol errors: unknown tool is -32602", %{
      conn: conn,
      token: token
    } do
      body = conn |> call_tool(token, "no_such_tool") |> json_response(400)
      assert body["error"]["code"] == -32_602
      assert body["error"]["message"] =~ "no_such_tool"
    end
  end

  describe "HTTP methods and origins" do
    test "GET and DELETE are 405 (no stream, no session)", %{conn: conn} do
      for {verb, fun} <- [{"GET", &get/2}, {"DELETE", &delete/2}] do
        conn = fun.(conn, ~p"/mcp")
        assert json_response(conn, 405)["error"] == "method_not_allowed", verb
        assert get_resp_header(conn, "allow") == ["POST, OPTIONS"]
      end
    end

    test "an unknown Origin is 403 while a Claude or loopback origin is served with CORS headers",
         %{conn: conn, token: token} do
      denied =
        mcp_post(conn, request("server/discover"),
          token: token,
          headers: %{"origin" => "https://evil.example"}
        )

      assert json_response(denied, 403)["error"]["code"] == -32_600
      assert get_resp_header(denied, "access-control-allow-origin") == []

      allowed =
        mcp_post(conn, request("server/discover"),
          token: token,
          headers: %{"origin" => "http://localhost:6274"}
        )

      assert json_response(allowed, 200)["result"]
      assert get_resp_header(allowed, "access-control-allow-origin") == ["http://localhost:6274"]

      preflight = conn |> put_req_header("origin", "https://claude.ai") |> options(~p"/mcp")
      assert response(preflight, 204)
      assert get_resp_header(preflight, "access-control-allow-origin") == ["https://claude.ai"]
    end
  end

  describe "tools/list" do
    test "returns the registry in a deterministic order with caching hints", %{
      conn: conn,
      token: token
    } do
      first = conn |> list_tools(token) |> result()
      second = conn |> list_tools(token) |> result()

      assert first["tools"] == second["tools"]
      assert Enum.map(first["tools"], & &1["name"]) == Enum.map(Registry.all(), & &1.name())
      assert first["ttlMs"] == 300_000
      assert first["cacheScope"] == "public"
      assert first["resultType"] == "complete"
      refute Map.has_key?(first, "nextCursor")
    end

    test "every tool has a title, annotations, schemas, and a name within Claude's limits", %{
      conn: conn,
      token: token
    } do
      for tool <- conn |> list_tools(token) |> result() |> Map.fetch!("tools") do
        assert tool["name"] =~ ~r/^[a-z][a-z0-9_]*$/
        assert String.length(tool["name"]) <= 30
        assert is_binary(tool["title"]) and tool["title"] != ""
        assert is_binary(tool["description"]) and tool["description"] != ""
        assert tool["inputSchema"]["type"] == "object"
        assert tool["outputSchema"]["type"] == "object"
        assert is_boolean(tool["annotations"]["readOnlyHint"])
        assert is_boolean(tool["annotations"]["destructiveHint"])
        assert is_boolean(tool["annotations"]["idempotentHint"])
        assert tool["annotations"]["title"] == tool["title"]
      end
    end

    test "an unknown cursor is -32602", %{conn: conn, token: token} do
      assert %{"error" => %{"code" => -32_602}} =
               conn |> list_tools(token, %{"cursor" => "bogus"}) |> json_response(400)
    end
  end

  describe "statelessness" do
    test "two independent requests with nothing in common succeed", %{conn: conn, token: token} do
      assert conn |> call_tool(token, "list_active_nets") |> structured()
      assert build_conn() |> call_tool(token, "get_my_profile") |> structured()
      assert build_conn() |> discover(token) |> result()
    end

    test "an Mcp-Session-Id header is ignored, never echoed", %{conn: conn, token: token} do
      conn =
        mcp_post(conn, request("server/discover"),
          token: token,
          headers: %{"mcp-session-id" => "abc"}
        )

      assert json_response(conn, 200)["result"]
      assert get_resp_header(conn, "mcp-session-id") == []
    end
  end

  describe "tools/call authorization" do
    test "a token whose scope the role could hold but does not carry is 403 insufficient_scope",
         %{conn: conn, member: member} do
      narrow = OAuthFixtures.access_token_fixture(member.user, scopes: ["emcomm:member"])
      conn = call_tool(conn, narrow, "list_ops")
      assert json_response(conn, 403)["error"] == "insufficient_scope"
      assert [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ ~s(error="insufficient_scope")
      assert challenge =~ ~s(scope="emcomm:operations")
      assert challenge =~ "resource_metadata="
    end

    test "a tool the role can never use is a tool error, not a step-up", %{
      conn: conn,
      token: token
    } do
      assert call_tool(conn, token, "list_pending_members") |> tool_error() =~ "administrator"
    end

    test "a pending member's token has no scopes and every tool tells them why", %{conn: conn} do
      pending = McEmcommFixtures.pending_member_fixture()
      token = OAuthFixtures.access_token_fixture(pending.user, scopes: [])
      assert call_tool(conn, token, "list_active_nets") |> tool_error() =~ "approved member"
    end

    test "invalid arguments are a tool error naming the field", %{conn: conn, token: token} do
      text = conn |> call_tool(token, "start_net", %{"aprs_keyword" => "x"}) |> tool_error()
      assert text =~ "aprs_keyword must be at least 2 characters"
    end
  end

  describe "trace context" do
    test "a traceparent in _meta is accepted", %{conn: conn, token: token} do
      body =
        request("server/discover", %{
          "_meta" =>
            meta(%{"traceparent" => "00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01"})
        })

      assert conn |> mcp_post(body, token: token) |> json_response(200)
    end
  end

  test "the protocol version constant is the one this server advertises" do
    assert Protocol.protocol_version() == "2026-07-28"
  end
end

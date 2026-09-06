defmodule McEmcomm.MCP.ProtocolTest do
  use ExUnit.Case, async: true

  alias McEmcomm.MCP.Protocol

  @meta %{"io.modelcontextprotocol/protocolVersion" => "2026-07-28"}

  describe "decode/1" do
    test "classifies requests and notifications" do
      assert {:request, 1, "tools/list", %{}} =
               Protocol.decode(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})

      assert {:request, "abc", "x", %{"a" => 1}} =
               Protocol.decode(%{
                 "jsonrpc" => "2.0",
                 "id" => "abc",
                 "method" => "x",
                 "params" => %{"a" => 1}
               })

      assert {:notification, "notifications/initialized", %{}} =
               Protocol.decode(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
    end

    test "rejects batches, responses, null ids, and non-messages" do
      assert {:error, -32_600, _, nil} =
               Protocol.decode([%{"jsonrpc" => "2.0", "id" => 1, "method" => "x"}])

      assert {:error, -32_600, _, nil} =
               Protocol.decode(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}})

      assert {:error, -32_600, _, nil} =
               Protocol.decode(%{"jsonrpc" => "2.0", "id" => nil, "method" => "x"})

      assert {:error, -32_600, _, nil} =
               Protocol.decode(%{"jsonrpc" => "2.0", "id" => 1, "method" => "x", "params" => []})

      assert {:error, -32_600, _, nil} = Protocol.decode(%{"method" => "x"})
      assert {:error, -32_600, _, nil} = Protocol.decode("hello")
    end
  end

  describe "validate_headers/3" do
    test "passes a well-formed tools/call" do
      headers = %{
        "mcp-protocol-version" => "2026-07-28",
        "mcp-method" => "tools/call",
        "mcp-name" => "start_net"
      }

      assert :ok =
               Protocol.validate_headers(headers, "tools/call", %{
                 "name" => "start_net",
                 "_meta" => @meta
               })
    end

    test "a Base64-sentinel Mcp-Name is decoded before comparison" do
      encoded = "=?base64?" <> Base.encode64("start_net") <> "?="

      headers = %{
        "mcp-protocol-version" => "2026-07-28",
        "mcp-method" => "tools/call",
        "mcp-name" => encoded
      }

      assert :ok =
               Protocol.validate_headers(headers, "tools/call", %{
                 "name" => "start_net",
                 "_meta" => @meta
               })
    end

    test "a missing or unsupported protocol version is -32022 with the supported list" do
      assert {:error, -32_022, _, data} =
               Protocol.validate_headers(%{}, "tools/list", %{"_meta" => @meta})

      assert data["supported"] == ["2026-07-28"]
      assert data["supportedVersions"] == ["2026-07-28"]

      assert {:error, -32_022, _, %{"requested" => "2025-11-25"}} =
               Protocol.validate_headers(
                 %{"mcp-protocol-version" => "2025-11-25"},
                 "tools/list",
                 %{"_meta" => @meta}
               )
    end

    test "_meta version absent is -32602; different from the header is -32020" do
      headers = %{"mcp-protocol-version" => "2026-07-28", "mcp-method" => "tools/list"}
      assert {:error, -32_602, _, nil} = Protocol.validate_headers(headers, "tools/list", %{})

      meta = %{"io.modelcontextprotocol/protocolVersion" => "2025-11-25"}

      assert {:error, -32_020, _, nil} =
               Protocol.validate_headers(headers, "tools/list", %{"_meta" => meta})
    end

    test "Mcp-Method and Mcp-Name must be present and agree with the body" do
      base = %{"mcp-protocol-version" => "2026-07-28"}
      params = %{"name" => "start_net", "_meta" => @meta}

      assert {:error, -32_020, _, nil} = Protocol.validate_headers(base, "tools/list", params)

      assert {:error, -32_020, _, nil} =
               Protocol.validate_headers(
                 Map.put(base, "mcp-method", "tools/call"),
                 "tools/list",
                 params
               )

      with_method = Map.put(base, "mcp-method", "tools/call")

      assert {:error, -32_020, _, nil} =
               Protocol.validate_headers(with_method, "tools/call", params)

      assert {:error, -32_020, _, nil} =
               Protocol.validate_headers(
                 Map.put(with_method, "mcp-name", "end_net"),
                 "tools/call",
                 params
               )

      assert {:error, -32_020, _, nil} =
               Protocol.validate_headers(
                 Map.put(with_method, "mcp-name", "=?base64?***?="),
                 "tools/call",
                 params
               )
    end
  end

  test "results carry resultType and serverInfo" do
    result = Protocol.result(%{"x" => 1})
    assert result["resultType"] == "complete"

    assert %{"name" => "mc_emcomm", "version" => _} =
             result["_meta"]["io.modelcontextprotocol/serverInfo"]
  end

  test "trace_carrier/1 extracts only the W3C keys" do
    params = %{
      "_meta" => %{
        "traceparent" => "00-abc-def-01",
        "baggage" => "k=v",
        "other" => "x",
        "tracestate" => 1
      }
    }

    assert Protocol.trace_carrier(params) == [
             {"traceparent", "00-abc-def-01"},
             {"baggage", "k=v"}
           ]
  end

  test "http_status/1 maps method-not-found to 404, internal to 500, the rest to 400" do
    assert Protocol.http_status(-32_601) == 404
    assert Protocol.http_status(-32_603) == 500
    assert Protocol.http_status(-32_022) == 400
  end
end

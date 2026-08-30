defmodule McEmcommWeb.MetricsEndpointTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias McEmcommWeb.MetricsEndpoint

  @opts MetricsEndpoint.init([])

  test "GET /metrics serves Prometheus text" do
    conn = :get |> conn("/metrics") |> MetricsEndpoint.call(@opts)

    assert conn.status == 200
    assert [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
    assert content_type =~ "text/plain"
    assert conn.resp_body =~ "mc_emcomm_prom_ex"
  end

  test "anything else is 404" do
    conn = :get |> conn("/") |> MetricsEndpoint.call(@opts)
    assert conn.status == 404
  end
end

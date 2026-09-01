defmodule McEmcommWeb.CacheControlTest do
  use McEmcommWeb.ConnCase, async: true

  # Every page carries a per-request CSP nonce, a CSRF token, and the session
  # cookie, so no shared cache (e.g. a CDN) may ever store one. The header must
  # say so explicitly rather than relying on cache heuristics.
  test "browser responses forbid caching", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "public LiveView responses forbid caching", %{conn: conn} do
    conn = get(conn, ~p"/about")

    assert html_response(conn, 200)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end
end

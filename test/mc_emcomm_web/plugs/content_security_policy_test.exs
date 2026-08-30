defmodule McEmcommWeb.Plugs.ContentSecurityPolicyTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias McEmcommWeb.Plugs.ContentSecurityPolicy

  @opts ContentSecurityPolicy.init([])

  defp policy(conn) do
    [policy] = Plug.Conn.get_resp_header(conn, "content-security-policy")
    policy
  end

  defp directives(conn) do
    conn
    |> policy()
    |> String.split("; ")
    |> Map.new(fn directive ->
      [name | sources] = String.split(directive, " ")
      {name, sources}
    end)
  end

  test "scripts are nonce-gated, never inline" do
    conn = :get |> conn("/") |> ContentSecurityPolicy.call(@opts)

    assert directives(conn)["script-src"] == ["'self'", "'nonce-#{conn.assigns.csp_nonce}'"]
  end

  test "a fresh nonce is assigned per request" do
    first = :get |> conn("/") |> ContentSecurityPolicy.call(@opts)
    second = :get |> conn("/") |> ContentSecurityPolicy.call(@opts)

    assert byte_size(first.assigns.csp_nonce) > 0
    refute first.assigns.csp_nonce == second.assigns.csp_nonce
  end

  test "locks down the directives that have no legitimate source" do
    directives = :get |> conn("/") |> ContentSecurityPolicy.call(@opts) |> directives()

    assert directives["default-src"] == ["'self'"]
    assert directives["object-src"] == ["'none'"]
    assert directives["base-uri"] == ["'self'"]
    assert directives["form-action"] == ["'self'"]
    assert directives["frame-ancestors"] == ["'self'"]
    assert "'self'" in directives["connect-src"]
  end

  test "names the configured map tile origin, not the whole URL template" do
    directives = :get |> conn("/") |> ContentSecurityPolicy.call(@opts) |> directives()

    tile_origin =
      :mc_emcomm |> Application.get_env(:map_tile_url) |> URI.parse() |> Map.get(:host)

    assert "https://#{tile_origin}" in directives["img-src"]
    refute Enum.any?(directives["img-src"], &String.contains?(&1, "{z}"))
  end
end

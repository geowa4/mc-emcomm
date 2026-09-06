defmodule McEmcommWeb.MCPDisabledTest do
  # Sync: flips the shared feature flag.
  use McEmcommWeb.ConnCase, async: false

  import McEmcommWeb.MCPHelpers

  setup do
    original = Application.fetch_env!(:mc_emcomm, :mcp)
    Application.put_env(:mc_emcomm, :mcp, Keyword.put(original, :enabled, false))
    on_exit(fn -> Application.put_env(:mc_emcomm, :mcp, original) end)
    :ok
  end

  test "every connector route is 404 while MC_EMCOMM_MCP_ENABLED is off", %{conn: conn} do
    assert conn |> get(~p"/.well-known/oauth-protected-resource") |> json_response(404)
    assert conn |> get(~p"/.well-known/oauth-authorization-server") |> json_response(404)
    assert conn |> post(~p"/oauth/register", %{}) |> json_response(404)
    assert conn |> post(~p"/oauth/token", %{}) |> json_response(404)
    assert conn |> mcp_post(request("server/discover")) |> json_response(404)
  end
end

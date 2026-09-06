defmodule McEmcommWeb.Plugs.MCPEnabled do
  @moduledoc """
  Answers 404 on every MCP and OAuth route while `MC_EMCOMM_MCP_ENABLED` is
  off, so a deployment that has not opted into the connector exposes none of
  its surface (SPEC.md §28).
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if McEmcomm.OAuth.enabled?() do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{"error" => "not_found"}))
      |> halt()
    end
  end
end

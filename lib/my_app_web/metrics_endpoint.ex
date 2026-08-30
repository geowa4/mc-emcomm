defmodule MyAppWeb.MetricsEndpoint do
  @moduledoc """
  Minimal plug pipeline for the private Prometheus listener: `GET /metrics`
  is served by `PromEx.Plug`; everything else is 404.
  """
  use Plug.Builder

  plug PromEx.Plug, prom_ex_module: MyApp.PromEx
  plug :not_found

  def not_found(conn, _opts), do: Plug.Conn.send_resp(conn, 404, "not found")
end

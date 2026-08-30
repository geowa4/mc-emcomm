defmodule McEmcomm.PromEx do
  @moduledoc """
  Prometheus metrics. Served by `McEmcommWeb.MetricsEndpoint` on the private
  metrics port; PromEx's own (Cowboy-based) metrics server is disabled.
  """
  use PromEx, otp_app: :mc_emcomm

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: McEmcommWeb.Router, endpoint: McEmcommWeb.Endpoint},
      PromEx.Plugins.Ecto
    ]
  end

  @impl true
  def dashboards, do: []
end

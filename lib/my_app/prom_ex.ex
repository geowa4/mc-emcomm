defmodule MyApp.PromEx do
  @moduledoc """
  Prometheus metrics. Served by `MyAppWeb.MetricsEndpoint` on the private
  metrics port; PromEx's own (Cowboy-based) metrics server is disabled.
  """
  use PromEx, otp_app: :my_app

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: MyAppWeb.Router, endpoint: MyAppWeb.Endpoint},
      PromEx.Plugins.Ecto
    ]
  end

  @impl true
  def dashboards, do: []
end

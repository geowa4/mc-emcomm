defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  @doc "Liveness: always 200, no dependencies."
  def live(conn, _params), do: send_resp(conn, 200, "ok")

  @doc "Readiness: reflects the cached database probe."
  def ready(conn, _params) do
    if MyApp.Health.Probe.ready?(),
      do: send_resp(conn, 200, "ready"),
      else: send_resp(conn, 503, "not ready")
  end

  @doc "Build identity: the git commit baked into the release image."
  def version(conn, _params) do
    json(conn, %{version: Application.fetch_env!(:my_app, :git_sha)})
  end
end

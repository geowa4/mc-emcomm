defmodule McEmcommWeb.HealthController do
  use McEmcommWeb, :controller

  @doc "Liveness: always 200, no dependencies."
  def live(conn, _params), do: send_resp(conn, 200, "ok")

  @doc "Readiness: reflects the cached database probe."
  def ready(conn, _params) do
    if McEmcomm.Health.Probe.ready?(),
      do: send_resp(conn, 200, "ready"),
      else: send_resp(conn, 503, "not ready")
  end

  @doc "Build identity: the git commit baked into the release image."
  def version(conn, _params) do
    json(conn, %{version: Application.fetch_env!(:mc_emcomm, :git_sha)})
  end
end

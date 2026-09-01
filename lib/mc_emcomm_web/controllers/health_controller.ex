defmodule McEmcommWeb.HealthController do
  use McEmcommWeb, :controller

  # A cached readiness (or liveness) answer defeats the probe: a CDN or proxy
  # replaying a stale 200 would hide an unready instance.
  plug :put_no_store_cache_control

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

  defp put_no_store_cache_control(conn, _opts) do
    put_resp_header(conn, "cache-control", "no-store")
  end
end

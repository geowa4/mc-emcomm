defmodule MyAppWeb.HealthControllerTest do
  # Toggles the shared readiness flag, so it must not run concurrently.
  use MyAppWeb.ConnCase, async: false

  @key {MyApp.Health.Probe, :ready?}

  setup do
    original = :persistent_term.get(@key, false)
    on_exit(fn -> :persistent_term.put(@key, original) end)
    :ok
  end

  test "GET /healthz/live always returns 200", %{conn: conn} do
    conn = get(conn, ~p"/healthz/live")
    assert response(conn, 200) == "ok"
  end

  test "GET /healthz/ready returns 200 when the probe succeeded", %{conn: conn} do
    :persistent_term.put(@key, true)
    assert response(get(conn, ~p"/healthz/ready"), 200) == "ready"
  end

  test "GET /healthz/ready returns 503 when the probe failed", %{conn: conn} do
    :persistent_term.put(@key, false)
    assert response(get(conn, ~p"/healthz/ready"), 503) == "not ready"
  end

  test "GET /healthz/version returns the configured git sha", %{conn: conn} do
    expected = Application.fetch_env!(:my_app, :git_sha)
    assert %{"version" => ^expected} = json_response(get(conn, ~p"/healthz/version"), 200)
  end
end

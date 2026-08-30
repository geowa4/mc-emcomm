defmodule McEmcommWeb.WebhookControllerTest do
  use McEmcommWeb.ConnCase, async: true

  import Ecto.Query

  import McEmcomm.ResendHelpers

  alias McEmcomm.Inbound.WebhookEvent
  alias McEmcomm.Repo

  defp event_count, do: Repo.aggregate(WebhookEvent, :count)

  test "a correctly signed event is acknowledged and recorded", %{conn: conn} do
    body = Jason.encode!(received_event(%{subject: "Signed"}))

    conn = conn |> sign_webhook(body, id: "msg_signed") |> post(~p"/webhooks/resend", body)

    assert response(conn, 200) == ""
    assert Repo.exists?(from e in WebhookEvent, where: e.svix_id == "msg_signed")
  end

  test "a redelivered event (same svix-id) is acknowledged but recorded once", %{conn: conn} do
    body = Jason.encode!(received_event())

    assert conn
           |> sign_webhook(body, id: "msg_dup")
           |> post(~p"/webhooks/resend", body)
           |> response(200)

    assert conn
           |> sign_webhook(body, id: "msg_dup")
           |> post(~p"/webhooks/resend", body)
           |> response(200)

    assert event_count() == 1
  end

  test "any matching signature among several passes", %{conn: conn} do
    body = Jason.encode!(received_event())
    id = "msg_multi"
    ts = System.system_time(:second)
    header = "v1,bm90LXRoZS1zaWduYXR1cmU= " <> signature(id, ts, body)

    conn =
      conn
      |> sign_webhook(body, id: id, timestamp: ts, signature: header)
      |> post(~p"/webhooks/resend", body)

    assert response(conn, 200)
    assert event_count() == 1
  end

  test "a signature tagged with another scheme is rejected", %{conn: conn} do
    body = Jason.encode!(received_event())
    id = "msg_scheme"
    ts = System.system_time(:second)
    # The bytes are a valid v1 signature; only the scheme tag differs.
    "v1," <> sig = signature(id, ts, body)

    conn =
      conn
      |> sign_webhook(body, id: id, timestamp: ts, signature: "v0," <> sig)
      |> post(~p"/webhooks/resend", body)

    assert response(conn, 401) == "invalid signature"
    assert event_count() == 0
  end

  test "a bad signature is rejected before any processing", %{conn: conn} do
    body = Jason.encode!(received_event())
    forged = "whsec_" <> Base.encode64("wrong-secret")

    conn = conn |> sign_webhook(body, secret: forged) |> post(~p"/webhooks/resend", body)

    assert response(conn, 401) == "invalid signature"
    assert event_count() == 0
  end

  test "a tampered body is rejected", %{conn: conn} do
    body = Jason.encode!(received_event())
    tampered = String.replace(body, "Hello", "Pwned")

    conn = conn |> sign_webhook(body) |> post(~p"/webhooks/resend", tampered)

    assert response(conn, 401)
    assert event_count() == 0
  end

  test "a stale timestamp is rejected", %{conn: conn} do
    body = Jason.encode!(received_event())
    stale = System.system_time(:second) - 301

    conn = conn |> sign_webhook(body, timestamp: stale) |> post(~p"/webhooks/resend", body)

    assert response(conn, 401)
  end

  test "missing svix headers are rejected", %{conn: conn} do
    body = Jason.encode!(received_event())

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/resend", body)

    assert response(conn, 401)
  end
end

defmodule MyAppWeb.WebhookControllerTest do
  use MyAppWeb.ConnCase, async: true

  import MyApp.ResendHelpers

  alias MyApp.Inbound

  setup do
    sender = unique_address("alice")
    Inbound.subscribe(sender)
    {:ok, sender: sender}
  end

  test "a correctly signed event is acknowledged and broadcast", %{conn: conn, sender: sender} do
    event = received_event(%{from: "Alice <#{sender}>", subject: "Signed"})
    body = Jason.encode!(event)
    email_id = event["data"]["email_id"]

    conn = conn |> sign_webhook(body) |> post(~p"/webhooks/resend", body)

    assert response(conn, 200) == ""
    assert_receive {:email_received, %{email_id: ^email_id, subject: "Signed"}}
  end

  test "a redelivered event (same svix-id) is acknowledged but not re-broadcast", %{
    conn: conn,
    sender: sender
  } do
    body = Jason.encode!(received_event(%{from: sender}))

    assert conn
           |> sign_webhook(body, id: "msg_dup")
           |> post(~p"/webhooks/resend", body)
           |> response(200)

    assert_receive {:email_received, _}

    assert conn
           |> sign_webhook(body, id: "msg_dup")
           |> post(~p"/webhooks/resend", body)
           |> response(200)

    refute_receive {:email_received, _}
  end

  test "any matching signature among several passes", %{conn: conn, sender: sender} do
    body = Jason.encode!(received_event(%{from: sender}))
    id = "msg_multi"
    ts = System.system_time(:second)
    header = "v1,bm90LXRoZS1zaWduYXR1cmU= " <> signature(id, ts, body)

    conn =
      conn
      |> sign_webhook(body, id: id, timestamp: ts, signature: header)
      |> post(~p"/webhooks/resend", body)

    assert response(conn, 200)
    assert_receive {:email_received, _}
  end

  test "a signature tagged with another scheme is rejected", %{conn: conn, sender: sender} do
    body = Jason.encode!(received_event(%{from: sender}))
    id = "msg_scheme"
    ts = System.system_time(:second)
    # The bytes are a valid v1 signature; only the scheme tag differs.
    "v1," <> sig = signature(id, ts, body)

    conn =
      conn
      |> sign_webhook(body, id: id, timestamp: ts, signature: "v0," <> sig)
      |> post(~p"/webhooks/resend", body)

    assert response(conn, 401) == "invalid signature"
    refute_receive {:email_received, _}
  end

  test "a bad signature is rejected before any processing", %{conn: conn, sender: sender} do
    body = Jason.encode!(received_event(%{from: sender}))
    forged = "whsec_" <> Base.encode64("wrong-secret")

    conn = conn |> sign_webhook(body, secret: forged) |> post(~p"/webhooks/resend", body)

    assert response(conn, 401) == "invalid signature"
    refute_receive {:email_received, _}
    assert MyApp.Repo.aggregate(MyApp.Inbound.WebhookEvent, :count) == 0
  end

  test "a tampered body is rejected", %{conn: conn, sender: sender} do
    body = Jason.encode!(received_event(%{from: sender}))
    tampered = String.replace(body, "Hello", "Pwned")

    conn = conn |> sign_webhook(body) |> post(~p"/webhooks/resend", tampered)

    assert response(conn, 401)
    refute_receive {:email_received, _}
  end

  test "a stale timestamp is rejected", %{conn: conn, sender: sender} do
    body = Jason.encode!(received_event(%{from: sender}))
    stale = System.system_time(:second) - 301

    conn = conn |> sign_webhook(body, timestamp: stale) |> post(~p"/webhooks/resend", body)

    assert response(conn, 401)
  end

  test "missing svix headers are rejected", %{conn: conn, sender: sender} do
    body = Jason.encode!(received_event(%{from: sender}))

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/resend", body)

    assert response(conn, 401)
  end
end

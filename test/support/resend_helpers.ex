defmodule McEmcomm.ResendHelpers do
  @moduledoc """
  Test helpers for the Resend webhook integration: Svix-style signing of
  webhook payloads and a builder for webhook events.
  """
  import Plug.Conn

  @doc "Signs `body` the way Svix/Resend do and puts the three headers on `conn`."
  def sign_webhook(conn, body, opts \\ []) do
    id = Keyword.get(opts, :id, "msg_" <> Integer.to_string(System.unique_integer([:positive])))
    ts = Keyword.get(opts, :timestamp, System.system_time(:second))

    secret =
      Keyword.get(opts, :secret, Application.fetch_env!(:mc_emcomm, :resend_webhook_secret))

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("svix-id", id)
    |> put_req_header("svix-timestamp", Integer.to_string(ts))
    |> put_req_header(
      "svix-signature",
      Keyword.get(opts, :signature, signature(id, ts, body, secret))
    )
  end

  def signature(
        id,
        ts,
        body,
        secret \\ Application.fetch_env!(:mc_emcomm, :resend_webhook_secret)
      ) do
    key = secret |> String.replace_prefix("whsec_", "") |> Base.decode64!()
    "v1," <> Base.encode64(:crypto.mac(:hmac, :sha256, key, "#{id}.#{ts}.#{body}"))
  end

  @doc "Builds an `email.received` webhook payload."
  def received_event(attrs \\ %{}) do
    data =
      Map.merge(
        %{
          "email_id" => "em_" <> Integer.to_string(System.unique_integer([:positive])),
          "created_at" => "2026-08-25T12:00:00.000Z",
          "from" => "Alice <alice@example.com>",
          "to" => ["inbound@mc-emcomm.example"],
          "bcc" => [],
          "cc" => [],
          "message_id" => "<abc@example.com>",
          "subject" => "Hello",
          "attachments" => []
        },
        Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
      )

    %{"type" => "email.received", "created_at" => data["created_at"], "data" => data}
  end
end

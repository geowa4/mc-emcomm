defmodule MyApp.Inbound.EmailTest do
  use ExUnit.Case, async: true

  import MyApp.ResendHelpers

  alias MyApp.Inbound.Email

  test "the webhook and the Receiving API produce the same shape" do
    from = "Alice <ALICE@Example.com>"

    webhook =
      Email.from_webhook(received_event(%{email_id: "em_1", from: from, subject: "Hi"})["data"])

    api = Email.from_api(received_email(%{id: "em_1", from: from, subject: "Hi"}))

    assert webhook == api

    assert %Email{
             id: "em_1",
             email_id: "em_1",
             from: "alice@example.com",
             to: ["inbound@my-app.example"],
             subject: "Hi",
             received_at: "2026-08-25T12:00:00.000Z"
           } = webhook
  end

  test "tolerates a payload with no sender or recipients" do
    assert %Email{from: "", to: [], subject: nil} = Email.from_api(%{"id" => "em_1"})
  end
end

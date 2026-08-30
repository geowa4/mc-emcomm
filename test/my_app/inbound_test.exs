defmodule MyApp.InboundTest do
  use MyApp.DataCase, async: true
  use ExUnitProperties

  import MyApp.ResendHelpers

  alias MyApp.Inbound
  alias MyApp.Inbound.Email

  describe "normalize/1" do
    test "extracts the address from display-name forms and downcases" do
      assert Inbound.normalize("Alice Example <Alice@Example.com>") == "alice@example.com"
      assert Inbound.normalize("  BOB@example.com ") == "bob@example.com"
      assert Inbound.normalize("<carol@example.com>") == "carol@example.com"
      assert Inbound.normalize(nil) == ""
    end

    property "is idempotent and never contains angle brackets or surrounding whitespace" do
      check all(
              local <- string(:alphanumeric, min_length: 1),
              domain <- string(:alphanumeric, min_length: 1),
              name <- string(:alphanumeric),
              form <- member_of([:bare, :bracketed, :named])
            ) do
        addr = "#{local}@#{domain}.example"

        input =
          case form do
            :bare -> "  #{String.upcase(addr)} "
            :bracketed -> "<#{addr}>"
            :named -> "#{name} <#{addr}>"
          end

        normalized = Inbound.normalize(input)
        assert normalized == String.downcase(addr)
        assert Inbound.normalize(normalized) == normalized
      end
    end
  end

  describe "topic_for/1" do
    test "uses the normalized address" do
      assert Inbound.topic_for("Alice <ALICE@example.com>") == "inbound_emails:alice@example.com"
    end
  end

  describe "record_event/2" do
    test "stores the svix id once and reports duplicates" do
      assert {:ok, event} = Inbound.record_event("msg_1", "email.received")
      assert event.svix_id == "msg_1"
      assert {:error, :duplicate} = Inbound.record_event("msg_1", "email.received")
    end

    test "requires a svix id" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        %MyApp.Inbound.WebhookEvent{}
        |> MyApp.Inbound.WebhookEvent.changeset(%{})
        |> Repo.insert!()
      end
    end
  end

  describe "handle_event/1" do
    test "broadcasts normalized metadata on the sender's topic" do
      addr = unique_address("alice")
      Inbound.subscribe(addr)
      event = received_event(%{from: "Alice <#{String.upcase(addr)}>", subject: "Hi"})
      email_id = event["data"]["email_id"]

      assert :ok = Inbound.handle_event(event)

      assert_receive {:email_received, %Email{email_id: ^email_id, from: ^addr, subject: "Hi"}}
    end

    test "ignores other event types" do
      addr = unique_address("alice")
      Inbound.subscribe(addr)

      assert :ok = Inbound.handle_event(%{"type" => "email.sent", "data" => %{"from" => addr}})

      refute_receive {:email_received, _}
    end
  end
end

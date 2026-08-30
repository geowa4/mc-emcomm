defmodule McEmcomm.InboundTest do
  use McEmcomm.DataCase, async: true

  import McEmcomm.ResendHelpers

  alias McEmcomm.Inbound

  describe "record_event/2" do
    test "stores the svix id once and reports duplicates" do
      assert {:ok, event} = Inbound.record_event("msg_1", "email.received")
      assert event.svix_id == "msg_1"
      assert {:error, :duplicate} = Inbound.record_event("msg_1", "email.received")
    end

    test "requires a svix id" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        %McEmcomm.Inbound.WebhookEvent{}
        |> McEmcomm.Inbound.WebhookEvent.changeset(%{})
        |> Repo.insert!()
      end
    end
  end

  describe "handle_event/1" do
    test "accepts any event" do
      assert :ok = Inbound.handle_event(received_event())
      assert :ok = Inbound.handle_event(%{"type" => "email.sent", "data" => %{}})
    end
  end
end

defmodule McEmcomm.OperationsTest do
  use McEmcomm.DataCase, async: true

  import Mox

  alias McEmcomm.AccountsFixtures
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Operations
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  # Downtown Rochester, NY — the operation fixture's default location.
  @in_radius %Geo.Point{coordinates: {-77.6090, 43.1568}, srid: 4326}
  # Buffalo, NY — ~90km away, outside any reasonable geofence.
  @far_away %Geo.Point{coordinates: {-78.8784, 42.8864}, srid: 4326}

  describe "match_location/2 — real PostGIS ST_DWithin/ST_Distance" do
    test "matches a point inside the geofence during the operation window" do
      operation = McEmcommFixtures.operation_fixture()
      now = DateTime.utc_now()

      assert {location, matched_operation} = Operations.match_location(@in_radius, now)
      assert matched_operation.id == operation.id
      assert location.name == "Primary Site"
    end

    test "does not match a point outside the geofence radius" do
      McEmcommFixtures.operation_fixture()
      now = DateTime.utc_now()

      assert Operations.match_location(@far_away, now) == nil
    end

    test "does not match before the operation window starts" do
      McEmcommFixtures.operation_fixture(%{
        "starts_at" => DateTime.add(DateTime.utc_now(), 3600, :second),
        "ends_at" => DateTime.add(DateTime.utc_now(), 7200, :second)
      })

      assert Operations.match_location(@in_radius, DateTime.utc_now()) == nil
    end

    test "does not match after the operation window ends (expired)" do
      McEmcommFixtures.operation_fixture(%{
        "starts_at" => DateTime.add(DateTime.utc_now(), -7200, :second),
        "ends_at" => DateTime.add(DateTime.utc_now(), -3600, :second)
      })

      assert Operations.match_location(@in_radius, DateTime.utc_now()) == nil
    end

    test "picks the nearest of two in-range locations, ordered by ST_Distance" do
      creator = AccountsFixtures.user_fixture()
      now = DateTime.utc_now()

      {:ok, operation} =
        Operations.create_operation_with_locations(
          %{
            "title" => "Multi-site",
            "starts_at" => DateTime.add(now, -3600, :second),
            "ends_at" => DateTime.add(now, 3600, :second),
            "visibility" => "members",
            "created_by_id" => creator.id
          },
          [
            %{
              "name" => "Near",
              "point" => %Geo.Point{coordinates: {-77.6090, 43.1568}, srid: 4326},
              "geofence_radius_m" => 2000
            },
            %{
              "name" => "Far",
              "point" => %Geo.Point{coordinates: {-77.6300, 43.1700}, srid: 4326},
              "geofence_radius_m" => 5000
            }
          ]
        )

      assert {location, matched} = Operations.match_location(@in_radius, now)
      assert matched.id == operation.id
      assert location.name == "Near"
    end
  end

  describe "list_operations/1 with :active_at" do
    test "keeps only operations whose window contains the instant" do
      now = DateTime.utc_now()
      current = McEmcommFixtures.operation_fixture(%{"title" => "Current"})

      McEmcommFixtures.operation_fixture(%{
        "title" => "Tomorrow",
        "starts_at" => DateTime.add(now, 86_400, :second),
        "ends_at" => DateTime.add(now, 90_000, :second)
      })

      McEmcommFixtures.operation_fixture(%{
        "title" => "Yesterday",
        "starts_at" => DateTime.add(now, -90_000, :second),
        "ends_at" => DateTime.add(now, -86_400, :second)
      })

      assert Enum.map(Operations.list_operations(active_at: now), & &1.id) == [current.id]
      assert Operations.active_id?(current.id)
      assert Enum.count(Operations.list_operations()) == 3
    end
  end

  describe "copy_operation/3" do
    test "copies locations and attachments to a new operation with its own window" do
      now = DateTime.utc_now()
      copier = AccountsFixtures.user_fixture()

      source =
        McEmcommFixtures.operation_fixture(
          %{"title" => "Field Day", "description" => "Annual", "visibility" => "public"},
          %{"name" => "HQ", "geofence_radius_m" => 250, "notes" => "Gate B"}
        )

      {:ok, _} =
        Operations.create_operation_attachment(%{
          operation_id: source.id,
          key: "operation-attachments/original.pdf",
          filename: "plan.pdf",
          content_type: "application/pdf",
          description: "Operations plan",
          uploaded_by_id: source.created_by_id
        })

      expect(StorageMock, :copy_object, fn "operation-attachments/original.pdf", new_key ->
        assert new_key =~ ~r/^operation-attachments\/[0-9a-f-]{36}\.pdf$/
        :ok
      end)

      attrs = %{
        "title" => "Field Day 2027",
        "description" => "Annual",
        "visibility" => "public",
        "starts_at" => DateTime.add(now, 86_400, :second),
        "ends_at" => DateTime.add(now, 90_000, :second),
        "created_by_id" => copier.id
      }

      assert {:ok, copy} = Operations.copy_operation(source, attrs, copier.id)
      copy = Operations.get_operation!(copy.id)

      assert copy.id != source.id
      assert copy.title == "Field Day 2027"
      assert copy.created_by_id == copier.id

      assert [location] = copy.locations
      assert location.name == "HQ"
      assert location.geofence_radius_m == 250
      assert location.notes == "Gate B"
      assert location.point.coordinates == hd(source.locations).point.coordinates

      assert [attachment] = copy.attachments
      assert attachment.filename == "plan.pdf"
      assert attachment.description == "Operations plan"
      assert attachment.uploaded_by_id == copier.id
      assert attachment.key != "operation-attachments/original.pdf"

      # The source is untouched.
      source = Operations.get_operation!(source.id)
      assert [%{key: "operation-attachments/original.pdf"}] = source.attachments
    end

    test "returns the operation changeset when the new window is invalid" do
      source = McEmcommFixtures.operation_fixture()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Operations.copy_operation(
                 source,
                 %{"title" => "No dates", "created_by_id" => source.created_by_id},
                 source.created_by_id
               )

      assert %{starts_at: ["can't be blank"]} = errors_on(changeset)
      assert Enum.count(Operations.list_operations()) == 1
    end
  end

  describe "rsvp/3" do
    test "records a response, replaces it on repeat, and orders the list going-first" do
      operation = McEmcommFixtures.operation_fixture()
      going = McEmcommFixtures.member_fixture(%{name: "Zed Going"})
      maybe = McEmcommFixtures.member_fixture(%{name: "Amy Maybe"})

      assert {:ok, rsvp} = Operations.rsvp(operation, going.id, %{"response" => "no"})
      assert rsvp.response == :no
      assert rsvp.note == nil

      assert {:ok, replaced} =
               Operations.rsvp(operation, going.id, %{"response" => "yes", "note" => "  1400  "})

      assert replaced.id == rsvp.id
      assert replaced.response == :yes
      assert replaced.note == "1400"

      assert {:ok, _} = Operations.rsvp(operation, maybe.id, %{"response" => "maybe"})

      assert [%{member_id: first}, %{member_id: second}] = Operations.list_rsvps(operation.id)
      assert {first, second} == {going.id, maybe.id}

      assert Operations.rsvp_counts(Operations.list_rsvps(operation.id)) == %{
               yes: 1,
               maybe: 1,
               no: 0
             }

      assert Operations.get_rsvp(operation.id, going.id).response == :yes
    end

    test "rejects an unknown response and an over-long note" do
      operation = McEmcommFixtures.operation_fixture()
      member = McEmcommFixtures.member_fixture()

      assert {:error, changeset} = Operations.rsvp(operation, member.id, %{"response" => "later"})
      assert %{response: [_]} = errors_on(changeset)

      note = String.duplicate("x", 501)

      assert {:error, changeset} =
               Operations.rsvp(operation, member.id, %{"response" => "yes", "note" => note})

      assert %{note: [_]} = errors_on(changeset)
      assert Operations.get_rsvp(operation.id, member.id) == nil
    end

    test "refuses once the operation has ended" do
      now = DateTime.utc_now()

      ended =
        McEmcommFixtures.operation_fixture(%{
          "starts_at" => DateTime.add(now, -7200, :second),
          "ends_at" => DateTime.add(now, -3600, :second)
        })

      member = McEmcommFixtures.member_fixture()

      assert Operations.ended?(ended)

      assert {:error, :operation_ended} =
               Operations.rsvp(ended, member.id, %{"response" => "yes"})

      assert Operations.list_rsvps(ended.id) == []
    end

    test "RSVPs go with the operation and with the member" do
      operation = McEmcommFixtures.operation_fixture()
      member = McEmcommFixtures.member_fixture()
      {:ok, _} = Operations.rsvp(operation, member.id, %{"response" => "yes"})

      {:ok, _} = Operations.delete_operation(operation)
      assert Operations.get_rsvp(operation.id, member.id) == nil

      other = McEmcommFixtures.operation_fixture()
      {:ok, _} = Operations.rsvp(other, member.id, %{"response" => "maybe"})
      {:ok, _} = McEmcomm.Members.delete_member(member)
      assert Operations.list_rsvps(other.id) == []
    end
  end
end

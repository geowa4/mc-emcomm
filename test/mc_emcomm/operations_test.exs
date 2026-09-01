defmodule McEmcomm.OperationsTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.AccountsFixtures
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Operations

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
end

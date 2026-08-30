defmodule McEmcomm.ExercisesTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.AccountsFixtures
  alias McEmcomm.Exercises
  alias McEmcomm.McEmcommFixtures

  # Downtown Rochester, NY — the exercise fixture's default location.
  @in_radius %Geo.Point{coordinates: {-77.6090, 43.1568}, srid: 4326}
  # Buffalo, NY — ~90km away, outside any reasonable geofence.
  @far_away %Geo.Point{coordinates: {-78.8784, 42.8864}, srid: 4326}

  describe "match_location/2 — real PostGIS ST_DWithin/ST_Distance" do
    test "matches a point inside the geofence during the exercise window" do
      exercise = McEmcommFixtures.exercise_fixture()
      now = DateTime.utc_now()

      assert {location, matched_exercise} = Exercises.match_location(@in_radius, now)
      assert matched_exercise.id == exercise.id
      assert location.name == "Primary Site"
    end

    test "does not match a point outside the geofence radius" do
      McEmcommFixtures.exercise_fixture()
      now = DateTime.utc_now()

      assert Exercises.match_location(@far_away, now) == nil
    end

    test "does not match before the exercise window starts" do
      McEmcommFixtures.exercise_fixture(%{
        "starts_at" => DateTime.add(DateTime.utc_now(), 3600, :second),
        "ends_at" => DateTime.add(DateTime.utc_now(), 7200, :second)
      })

      assert Exercises.match_location(@in_radius, DateTime.utc_now()) == nil
    end

    test "does not match after the exercise window ends (expired)" do
      McEmcommFixtures.exercise_fixture(%{
        "starts_at" => DateTime.add(DateTime.utc_now(), -7200, :second),
        "ends_at" => DateTime.add(DateTime.utc_now(), -3600, :second)
      })

      assert Exercises.match_location(@in_radius, DateTime.utc_now()) == nil
    end

    test "picks the nearest of two in-range locations, ordered by ST_Distance" do
      creator = AccountsFixtures.user_fixture()
      now = DateTime.utc_now()

      {:ok, exercise} =
        Exercises.create_exercise_with_locations(
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

      assert {location, matched} = Exercises.match_location(@in_radius, now)
      assert matched.id == exercise.id
      assert location.name == "Near"
    end
  end
end

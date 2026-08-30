defmodule McEmcomm.SightingsTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.Exercises
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Sightings

  @in_radius %Geo.Point{coordinates: {-77.6090, 43.1568}, srid: 4326}

  describe "record_visit/1 — update point 0 (HTTP mount)" do
    test "creates a sighting row from request metadata" do
      asset = McEmcommFixtures.asset_fixture()

      assert {:ok, sighting} =
               Sightings.record_visit(%{
                 asset_id: asset.id,
                 session_token: "tok-123",
                 visited_at: DateTime.utc_now(),
                 remote_ip: "203.0.113.5",
                 user_agent: "TestAgent/1.0"
               })

      assert sighting.asset_id == asset.id
      assert sighting.session_token == "tok-123"
      assert is_nil(sighting.submitted_at)
    end

    test "requires asset_id and session_token" do
      assert {:error, changeset} = Sightings.record_visit(%{visited_at: DateTime.utc_now()})

      assert %{asset_id: ["can't be blank"], session_token: ["can't be blank"]} =
               errors_on(changeset)
    end
  end

  describe "record_client_env/2 — update point 1a (socket connect)" do
    test "updates the row with client environment fields" do
      sighting = visited_sighting_fixture()

      assert {:ok, updated} =
               Sightings.record_client_env(sighting, %{
                 "connected_at" => DateTime.utc_now(),
                 "timezone" => "America/New_York",
                 "screen_w" => 390,
                 "screen_h" => 844,
                 "touch" => true
               })

      assert updated.timezone == "America/New_York"
      assert updated.touch == true
      refute is_nil(updated.connected_at)
    end
  end

  describe "record_geolocation/2 — update point 1b (grant/deny)" do
    test "grant: stores the point and accuracy" do
      sighting = visited_sighting_fixture()

      assert {:ok, updated} =
               Sightings.record_geolocation(sighting, %{
                 "located_at" => DateTime.utc_now(),
                 "point" => @in_radius,
                 "accuracy" => 12.5
               })

      assert %Geo.Point{} = updated.point
      assert updated.geo_denied == false
    end

    test "deny: sets geo_denied without a point" do
      sighting = visited_sighting_fixture()

      assert {:ok, updated} = Sightings.record_geolocation(sighting, %{"geo_denied" => true})

      assert updated.geo_denied == true
      assert is_nil(updated.point)
    end
  end

  describe "submit/3 — update point 2 (form submit)" do
    test "auto-links an approved member by call sign" do
      member = McEmcommFixtures.member_fixture(%{call_sign: "W2ABC"})
      sighting = visited_sighting_fixture()

      assert {:ok, updated} =
               Sightings.submit(sighting, %{"call_sign" => "w2abc", "note" => "all good"})

      assert updated.member_id == member.id
      assert updated.call_sign == "W2ABC"
      refute is_nil(updated.submitted_at)
    end

    test "does not link an unrecognized call sign" do
      sighting = visited_sighting_fixture()

      assert {:ok, updated} = Sightings.submit(sighting, %{"call_sign" => "N0CALL"})

      assert is_nil(updated.member_id)
    end

    test "uses current_member when the submitter is logged in, ignoring a mismatched call sign" do
      member = McEmcommFixtures.member_fixture()
      sighting = visited_sighting_fixture()

      assert {:ok, updated} =
               Sightings.submit(sighting, %{"call_sign" => "SOMEONE-ELSE"},
                 current_member: member
               )

      assert updated.member_id == member.id
    end

    test "geofence match creates exercise_attendance (source: asset_checkin) for an approved member" do
      exercise = McEmcommFixtures.exercise_fixture()
      member = McEmcommFixtures.member_fixture(%{call_sign: "W2GEO"})

      sighting = visited_sighting_fixture()
      {:ok, sighting} = Sightings.record_geolocation(sighting, %{"point" => @in_radius})

      assert {:ok, submitted} = Sightings.submit(sighting, %{"call_sign" => "W2GEO"})

      assert submitted.exercise_id == exercise.id
      assert submitted.exercise_location_id

      [attendance] = Exercises.list_attendance(exercise.id)
      assert attendance.member_id == member.id
      assert attendance.source == :asset_checkin
      assert attendance.sighting_id == submitted.id
    end

    test "no attendance is created without a geofence match" do
      member = McEmcommFixtures.member_fixture(%{call_sign: "W2NOM"})
      exercise = McEmcommFixtures.exercise_fixture()
      sighting = visited_sighting_fixture()

      assert {:ok, submitted} = Sightings.submit(sighting, %{"call_sign" => "W2NOM"})

      assert is_nil(submitted.exercise_id)
      assert Exercises.list_attendance(exercise.id) == []
      refute is_nil(member.id)
    end
  end

  describe "list_for_asset_member_view/1 vs list_for_asset_admin_view/1 — admin-only columns (§3, §7.11)" do
    test "the member-view projection never returns identity/visit, client-env, or geolocation columns" do
      asset = McEmcommFixtures.asset_fixture()

      {:ok, sighting} =
        Sightings.record_visit(%{
          asset_id: asset.id,
          session_token: "tok-secret",
          visited_at: DateTime.utc_now(),
          remote_ip: "203.0.113.9",
          user_agent: "SecretAgent/1.0"
        })

      {:ok, sighting} =
        Sightings.record_client_env(sighting, %{
          "timezone" => "America/New_York",
          "screen_w" => 1024
        })

      {:ok, sighting} =
        Sightings.record_geolocation(sighting, %{"point" => @in_radius, "accuracy" => 5.0})

      {:ok, _sighting} =
        Sightings.submit(sighting, %{"call_sign" => "W2SEE", "note" => "visible note"})

      [member_row] = Sightings.list_for_asset_member_view(asset.id)
      [admin_row] = Sightings.list_for_asset_admin_view(asset.id)

      # Submission-group fields (allowed) come through on both projections.
      assert member_row.call_sign == "W2SEE"
      assert admin_row.call_sign == "W2SEE"

      # Admin-only columns are absent from the member projection at the
      # query layer (never selected, not merely hidden in the template) —
      # while the admin projection has them populated.
      assert member_row.remote_ip == nil
      assert member_row.user_agent == nil
      assert member_row.session_token == nil
      assert member_row.timezone == nil
      assert member_row.point == nil
      assert member_row.visited_at == nil

      assert admin_row.remote_ip != nil
      assert admin_row.user_agent == "SecretAgent/1.0"
      assert admin_row.session_token == "tok-secret"
      assert admin_row.timezone == "America/New_York"
      assert %Geo.Point{} = admin_row.point
      assert admin_row.visited_at != nil
    end
  end

  describe "scrub_before/1 — retention (§20)" do
    test "nulls raw telemetry for sightings visited before the cutoff, keeps submission fields" do
      asset = McEmcommFixtures.asset_fixture()
      old_visit = DateTime.add(DateTime.utc_now(), -120, :day)

      {:ok, old_sighting} =
        Sightings.record_visit(%{
          asset_id: asset.id,
          session_token: "old-tok",
          visited_at: old_visit,
          remote_ip: "203.0.113.9",
          user_agent: "OldAgent/1.0"
        })

      {:ok, old_sighting} = Sightings.record_geolocation(old_sighting, %{"point" => @in_radius})
      {:ok, _old_sighting} = Sightings.submit(old_sighting, %{"call_sign" => "W2OLD"})

      {:ok, recent_sighting} =
        Sightings.record_visit(%{
          asset_id: asset.id,
          session_token: "recent-tok",
          visited_at: DateTime.utc_now(),
          remote_ip: "203.0.113.10"
        })

      cutoff = DateTime.add(DateTime.utc_now(), -90, :day)
      Sightings.scrub_before(cutoff)

      scrubbed = Sightings.get!(old_sighting.id)
      assert scrubbed.remote_ip == nil
      assert scrubbed.user_agent == nil
      assert scrubbed.point == nil
      refute is_nil(scrubbed.scrubbed_at)
      # Submission-group fields survive the scrub.
      assert scrubbed.call_sign == "W2OLD"

      untouched = Sightings.get!(recent_sighting.id)
      assert untouched.remote_ip != nil
      assert is_nil(untouched.scrubbed_at)
    end
  end

  defp visited_sighting_fixture do
    asset = McEmcommFixtures.asset_fixture()

    {:ok, sighting} =
      Sightings.record_visit(%{
        asset_id: asset.id,
        session_token: "tok-#{System.unique_integer()}",
        visited_at: DateTime.utc_now()
      })

    sighting
  end
end

defmodule McEmcommWeb.SightingLive.ShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.Exercises
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Sightings

  test "renders only the asset image, name, and form", %{conn: conn} do
    asset = McEmcommFixtures.asset_fixture(%{name: "Field Go-Kit"})

    {:ok, _lv, html} = live(conn, ~p"/a/#{asset.public_id}/s")

    assert html =~ "Field Go-Kit"
    assert html =~ "Submit sighting"
    refute html =~ "Sighting log"
  end

  test "redirects for an unknown public_id", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/a/ZZZZZZ/s")
  end

  test "the full three-update-point flow: connect, geolocation, and submit", %{conn: conn} do
    exercise = McEmcommFixtures.exercise_fixture()
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2SIT"})
    asset = McEmcommFixtures.asset_fixture()

    {:ok, lv, _html} = live(conn, ~p"/a/#{asset.public_id}/s")

    render_hook(lv, "client_env", %{
      "timezone" => "America/New_York",
      "screen_w" => 390,
      "screen_h" => 844,
      "touch" => true
    })

    render_hook(lv, "geolocation", %{"lat" => 43.1568, "lng" => -77.6090, "accuracy" => 5.0})

    html =
      lv
      |> form("#sighting-form", sighting: %{call_sign: "w2sit", note: "all clear"})
      |> render_submit()

    assert html =~ "Thanks"

    [sighting] = Sightings.list_for_asset_admin_view(asset.id)
    assert sighting.timezone == "America/New_York"
    assert sighting.touch == true
    assert %Geo.Point{} = sighting.point
    assert sighting.member_id == member.id
    assert sighting.exercise_id == exercise.id

    assert [attendance] = Exercises.list_attendance(exercise.id)
    assert attendance.sighting_id == sighting.id
    assert attendance.source == :asset_checkin
  end

  test "geolocation denial is recorded", %{conn: conn} do
    asset = McEmcommFixtures.asset_fixture()
    {:ok, lv, _html} = live(conn, ~p"/a/#{asset.public_id}/s")

    render_hook(lv, "geolocation_denied", %{})

    [sighting] = Sightings.list_for_asset_admin_view(asset.id)
    assert sighting.geo_denied == true
  end
end

defmodule McEmcommWeb.InventoryLive.ShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Sightings

  setup do
    asset = McEmcommFixtures.asset_fixture(%{name: "Field Go-Kit"})

    {:ok, sighting} =
      Sightings.record_visit(%{
        asset_id: asset.id,
        session_token: "tok",
        visited_at: DateTime.utc_now(),
        remote_ip: "203.0.113.5",
        user_agent: "SecretAgent/1.0"
      })

    {:ok, _sighting} = Sightings.submit(sighting, %{"call_sign" => "W2SEE", "note" => "spotted"})

    %{asset: asset}
  end

  test "a member sees the submission log but no map and no admin-only columns", %{
    conn: conn,
    asset: asset
  } do
    member = McEmcommFixtures.member_fixture()

    {:ok, _lv, html} =
      conn |> log_in_user(member.user) |> live(~p"/app/inventory/#{asset.public_id}")

    assert html =~ "Recent activity"
    assert html =~ "W2SEE"
    refute html =~ "Sighting map"
    refute html =~ "203.0.113.5"
    refute html =~ "SecretAgent"
  end

  test "an admin sees the full sighting log, map, and admin-only columns", %{
    conn: conn,
    asset: asset
  } do
    scope = McEmcommFixtures.admin_scope_fixture()

    {:ok, _lv, html} =
      conn |> log_in_user(scope.user) |> live(~p"/app/inventory/#{asset.public_id}")

    assert html =~ "Sighting log"
    assert html =~ "Sighting map"
    assert html =~ "W2SEE"
    assert html =~ "203.0.113.5"
  end

  test "the map filter defaults to the last seen date and supports last-N modes", %{
    conn: conn,
    asset: asset
  } do
    last_seen = DateTime.add(DateTime.utc_now(), -5, :day)

    {:ok, located} =
      Sightings.record_visit(%{
        asset_id: asset.id,
        session_token: "tok-geo",
        visited_at: last_seen
      })

    {:ok, _located} =
      Sightings.record_geolocation(located, %{
        "point" => %Geo.Point{coordinates: {-77.6090, 43.1568}, srid: 4326}
      })

    scope = McEmcommFixtures.admin_scope_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(scope.user) |> live(~p"/app/inventory/#{asset.public_id}")

    # Defaults to since-mode, prefilled with the last located sighting's date.
    assert has_element?(lv, "#map-filter-since[value='#{DateTime.to_date(last_seen)}']")

    # Switching to a last-N mode hides the date input.
    lv |> element("#map-filter") |> render_change(%{"mode" => "5"})
    refute has_element?(lv, "#map-filter-since")

    # Switching back to since-mode restores the date input with a chosen date.
    lv |> element("#map-filter") |> render_change(%{"mode" => "since", "since" => "2026-08-01"})
    assert has_element?(lv, "#map-filter-since[value='2026-08-01']")
  end

  test "a member never sees the map filter", %{conn: conn, asset: asset} do
    member = McEmcommFixtures.member_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(member.user) |> live(~p"/app/inventory/#{asset.public_id}")

    refute has_element?(lv, "#map-filter")
  end

  test "redirects for an unknown public_id", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()

    assert {:error, {:live_redirect, %{to: "/app/inventory"}}} =
             conn |> log_in_user(member.user) |> live(~p"/app/inventory/ZZZZZZ")
  end
end

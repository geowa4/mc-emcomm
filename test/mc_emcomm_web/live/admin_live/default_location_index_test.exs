defmodule McEmcommWeb.AdminLive.DefaultLocationIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.Locations
  alias McEmcomm.McEmcommFixtures

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "creating a location from a dropped pin", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/locations")

    lv |> element("button", "New location") |> render_click()
    assert has_element?(lv, "#default-location-form")

    render_hook(lv, "point_selected", %{"lat" => 43.21, "lng" => -77.55})

    html =
      lv
      |> form("#default-location-form", default_location: %{name: "NE", position: 2})
      |> render_submit()

    assert html =~ "NE"
    assert [location] = Locations.list_default_locations()
    assert location.name == "NE"
    assert location.position == 2
    assert location.point.coordinates == {-77.55, 43.21}
  end

  test "creating a location from typed coordinates", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/locations")

    lv |> element("button", "New location") |> render_click()
    assert has_element?(lv, "#default-location-map[role='application'][aria-label]")

    lv
    |> form("#default-location-map-coordinates", %{"lat" => "43.21", "lng" => "-77.55"})
    |> render_submit()

    assert_push_event(lv, "picker:set_point", %{
      id: "default-location-map",
      lat: 43.21,
      lng: -77.55
    })

    assert has_element?(lv, "#default-location-pending-point", "43.21")

    lv
    |> form("#default-location-form", default_location: %{name: "Typed", position: 1})
    |> render_submit()

    assert [location] = Locations.list_default_locations()
    assert location.point.coordinates == {-77.55, 43.21}
  end

  test "unusable coordinates are reported instead of applied", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/locations")

    lv |> element("button", "New location") |> render_click()

    html =
      lv
      |> form("#default-location-map-coordinates", %{"lat" => "95", "lng" => "-77.55"})
      |> render_submit()

    assert html =~ "Enter a latitude from -90 to 90"
    refute_push_event(lv, "picker:set_point", %{})
    assert has_element?(lv, "#default-location-pending-point", "No new point set")
  end

  test "editing without re-dropping a pin keeps the point", %{conn: conn} do
    location = McEmcommFixtures.default_location_fixture(%{name: "SW"})

    {:ok, lv, _html} = live(conn, ~p"/admin/locations")

    lv |> element("button", "Edit") |> render_click()
    lv |> form("#default-location-form", default_location: %{name: "SW Rally"}) |> render_submit()

    reloaded = Locations.get_default_location!(location.id)
    assert reloaded.name == "SW Rally"
    assert reloaded.point.coordinates == location.point.coordinates
  end

  test "deleting a location", %{conn: conn} do
    McEmcommFixtures.default_location_fixture(%{name: "NW"})

    {:ok, lv, _html} = live(conn, ~p"/admin/locations")

    lv |> element("button", "Delete") |> render_click()
    assert Locations.list_default_locations() == []
  end

  test "cancel clears the form without saving", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/locations")

    lv |> element("button", "New location") |> render_click()
    assert has_element?(lv, "#default-location-form")

    lv |> element("button", "Cancel") |> render_click()
    refute has_element?(lv, "#default-location-form")
    assert Locations.list_default_locations() == []
  end
end

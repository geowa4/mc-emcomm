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

  test "editing without re-dropping a pin keeps the point", %{conn: conn} do
    location = McEmcommFixtures.default_location_fixture(%{name: "SW"})

    {:ok, lv, _html} = live(conn, ~p"/admin/locations")

    lv |> element("a", "Edit") |> render_click()
    lv |> form("#default-location-form", default_location: %{name: "SW Rally"}) |> render_submit()

    reloaded = Locations.get_default_location!(location.id)
    assert reloaded.name == "SW Rally"
    assert reloaded.point.coordinates == location.point.coordinates
  end

  test "deleting a location", %{conn: conn} do
    McEmcommFixtures.default_location_fixture(%{name: "NW"})

    {:ok, lv, _html} = live(conn, ~p"/admin/locations")

    lv |> element("a", "Delete") |> render_click()
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

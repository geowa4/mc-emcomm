defmodule McEmcommWeb.PublicLive.CalendarTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the calendar embed", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/calendar")

    assert html =~ "Calendar"
    assert html =~ "calendar.google.com/calendar/embed"
    assert html =~ "c_47a34a906f34ba27c6cacde7a168a110957160035817b408d2553b62434fc3f7"
  end

  test "offers subscribe and ICS links", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/calendar")

    assert has_element?(lv, "#copy-ics-btn")
    assert html =~ "calendar.google.com/calendar/ical/"
    assert html =~ "public/basic.ics"
  end

  test "shows the site footer", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/calendar")

    assert has_element?(lv, "#site-footer")
    assert has_element?(lv, "#site-footer a[href='https://www.facebook.com/MCARESNY']")
  end
end

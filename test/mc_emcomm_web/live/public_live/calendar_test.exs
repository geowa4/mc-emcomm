defmodule McEmcommWeb.PublicLive.CalendarTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the calendar embed", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/calendar")

    assert html =~ "Calendar"
    assert html =~ "calendar.google.com/calendar/embed"
  end
end

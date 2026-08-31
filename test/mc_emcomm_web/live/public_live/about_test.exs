defmodule McEmcommWeb.PublicLive.AboutTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  test "lists every position as vacant when nobody holds one", %{conn: conn} do
    McEmcommFixtures.position_fixture(%{name: "President", sort_order: 1})
    McEmcommFixtures.position_fixture(%{name: "Secretary", sort_order: 2})

    {:ok, lv, html} = live(conn, ~p"/about")

    assert html =~ "About Monroe County ARES/RACES"
    assert has_element?(lv, "#leadership-list")

    for position <- Members.list_positions() do
      assert has_element?(lv, "#position-#{position.id}", position.name)
      assert has_element?(lv, "#position-#{position.id}", "Vacant")
    end
  end

  test "renders holders under their positions", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{name: "Riley Officer", call_sign: "W2LDR"})
    secretary = McEmcommFixtures.position_fixture(%{name: "Secretary"})
    {:ok, _} = Members.update_member_positions(member, [secretary.id])

    {:ok, lv, html} = live(conn, ~p"/about")

    assert has_element?(lv, "#position-#{secretary.id}", "Riley Officer")
    assert has_element?(lv, "#position-#{secretary.id}", "W2LDR")
    refute has_element?(lv, "#position-#{secretary.id}", "Vacant")
    assert html =~ "Secretary"
  end

  test "shows the social and community links", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/about")

    assert has_element?(lv, "#social-links a[href='https://www.facebook.com/MCARESNY']")
    assert has_element?(lv, "#social-links a[href='https://x.com/MCARESNY']")
    assert has_element?(lv, "#social-links a[href='https://groups.io/g/MonroeCountyEmcomm']")
  end
end

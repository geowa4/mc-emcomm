defmodule McEmcommWeb.AdminLive.PositionIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "creating, editing, and deleting a position", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("button", "New position") |> render_click()
    assert has_element?(lv, "#position-modal")

    html =
      lv
      |> form("#position-form", position: %{name: "President", sort_order: 1})
      |> render_submit()

    assert html =~ "President"

    position = Enum.find(Members.list_positions(), &(&1.name == "President"))

    lv |> element("a", "Edit") |> render_click()
    lv |> form("#position-form", position: %{name: "Club President"}) |> render_submit()
    assert Members.get_position!(position.id).name == "Club President"

    lv |> element("a", "Delete") |> render_click()
    assert Members.list_positions() == []
  end

  test "a position created with the admin checkbox grants admin and shows a badge", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("button", "New position") |> render_click()

    lv
    |> form("#position-form", position: %{name: "President", sort_order: 1, grants_admin: true})
    |> render_submit()

    position = Enum.find(Members.list_positions(), &(&1.name == "President"))
    assert position.grants_admin
    assert has_element?(lv, "#position-row-#{position.id} .badge", "admin")
  end

  test "holding an admin-granting position opens the admin area" do
    member = McEmcommFixtures.member_fixture(%{name: "Avery Holder"})
    position = McEmcommFixtures.position_fixture(%{name: "President", grants_admin: true})
    {:ok, _} = Members.assign_position(member, position)

    conn = log_in_user(build_conn(), member.user)
    assert {:ok, lv, _html} = live(conn, ~p"/admin/positions")
    assert has_element?(lv, "#nav-admin")
  end

  test "holding an ordinary position does not open the admin area" do
    member = McEmcommFixtures.member_fixture(%{name: "Avery Holder"})
    position = McEmcommFixtures.position_fixture(%{name: "Secretary"})
    {:ok, _} = Members.assign_position(member, position)

    conn = log_in_user(build_conn(), member.user)
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/positions")

    assert {:ok, lv, _html} = live(conn, ~p"/about")
    refute has_element?(lv, "#nav-admin")
  end

  test "deleting a held position is refused with a flash", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{name: "Avery Holder"})
    position = McEmcommFixtures.position_fixture(%{name: "Treasurer"})
    {:ok, _} = Members.update_member_positions(member, [position.id])

    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    html = lv |> element("a", "Delete") |> render_click()

    assert html =~ "A member holds that position"
    assert Members.get_position!(position.id)
  end

  test "a non-positive sort order shows an error and does not save", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("button", "New position") |> render_click()

    html =
      lv
      |> form("#position-form", position: %{name: "Net Manager", sort_order: -25})
      |> render_submit()

    assert html =~ "must be greater than 0"
    assert Members.list_positions() == []
  end

  test "dragging rows reorders the positions", %{conn: conn} do
    a = McEmcommFixtures.position_fixture(%{name: "President", sort_order: 1})
    b = McEmcommFixtures.position_fixture(%{name: "Secretary", sort_order: 2})
    c = McEmcommFixtures.position_fixture(%{name: "Treasurer", sort_order: 3})

    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv
    |> element("#positions-rows")
    |> render_hook("reorder", %{"ids" => ["#{c.id}", "#{a.id}", "#{b.id}"]})

    assert Enum.map(Members.list_positions(), & &1.name) == [
             "Treasurer",
             "President",
             "Secretary"
           ]
  end

  test "a stale reorder is refused and the list re-rendered", %{conn: conn} do
    a = McEmcommFixtures.position_fixture(%{name: "President", sort_order: 1})
    McEmcommFixtures.position_fixture(%{name: "Secretary", sort_order: 2})

    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    html =
      lv
      |> element("#positions-rows")
      |> render_hook("reorder", %{"ids" => ["#{a.id}"]})

    assert html =~ "The list changed underneath you"
    assert Enum.map(Members.list_positions(), & &1.sort_order) == [1, 2]
  end

  test "changing a position's holder by call sign search", %{conn: conn} do
    member_a = McEmcommFixtures.member_fixture(%{name: "Avery Holder", call_sign: "W2AAA"})
    member_b = McEmcommFixtures.member_fixture(%{name: "Blake Taker", call_sign: "W2BBB"})
    position = McEmcommFixtures.position_fixture(%{name: "Treasurer"})
    {:ok, _} = Members.update_member_positions(member_a, [position.id])

    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("#change-holder-#{position.id}") |> render_click()
    assert has_element?(lv, "#holder-modal")

    lv |> form("#holder-search-form", %{"call_sign" => "2bb"}) |> render_submit()
    assert has_element?(lv, "#holder-results", "W2BBB")

    lv |> element("#holder-results button", "Blake Taker") |> render_click()

    position_after = Enum.find(Members.list_positions(), &(&1.name == "Treasurer"))
    assert [%{id: id}] = position_after.members
    assert id == member_b.id
    refute has_element?(lv, "#holder-modal")
  end

  test "a search with no matches shows an empty state", %{conn: conn} do
    position = McEmcommFixtures.position_fixture(%{name: "Treasurer"})

    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("#change-holder-#{position.id}") |> render_click()
    lv |> form("#holder-search-form", %{"call_sign" => "ZZ9"}) |> render_submit()

    assert has_element?(lv, "#holder-results", "No members match that call sign.")
  end

  test "the holder search excludes non-approved members", %{conn: conn} do
    McEmcommFixtures.pending_member_fixture(%{name: "Pat Pending", call_sign: "W2PEN"})
    position = McEmcommFixtures.position_fixture(%{name: "Treasurer"})

    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("#change-holder-#{position.id}") |> render_click()
    lv |> form("#holder-search-form", %{"call_sign" => "W2PEN"}) |> render_submit()

    assert has_element?(lv, "#holder-results", "No members match that call sign.")
  end

  test "vacating a position from the holder modal", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{name: "Avery Holder", call_sign: "W2AAA"})
    position = McEmcommFixtures.position_fixture(%{name: "Treasurer"})
    {:ok, _} = Members.update_member_positions(member, [position.id])

    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("#change-holder-#{position.id}") |> render_click()
    lv |> element("#holder-modal button", "Vacate") |> render_click()

    position_after = Enum.find(Members.list_positions(), &(&1.name == "Treasurer"))
    assert position_after.members == []
    refute has_element?(lv, "#holder-modal")
  end

  test "cancel clears the form without saving", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("button", "New position") |> render_click()
    assert has_element?(lv, "#position-form")

    lv |> element("button", "Cancel") |> render_click()
    refute has_element?(lv, "#position-form")
  end

  test "clicking the modal backdrop closes the form", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/positions")

    lv |> element("button", "New position") |> render_click()
    assert has_element?(lv, "#position-modal")

    lv |> element("#position-modal .modal-backdrop") |> render_click()
    refute has_element?(lv, "#position-modal")
  end
end

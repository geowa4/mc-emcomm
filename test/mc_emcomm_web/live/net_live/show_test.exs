defmodule McEmcommWeb.NetLive.ShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "checking in adds to the roster and broadcasts to other viewers", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    other_member = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH", quadrant: :SE})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    lv
    |> form("#checkin-form", net_checkin: %{call_sign: "w2oth", notes: "loud and clear"})
    |> render_submit()

    assert render(lv) =~ "W2OTH"
    assert render(lv) =~ "SE"
    # The second viewer receives the check-in over PubSub without resubmitting.
    assert render(other_lv) =~ "W2OTH"
  end

  test "renaming a net via the pencil updates the name for other viewers", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    other_member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    lv |> element("#edit-net-name") |> render_click()
    assert has_element?(lv, "#net-name-form")

    lv |> form("#net-name-form", net_session: %{name: "Severe Weather Net"}) |> render_submit()

    refute has_element?(lv, "#net-name-form")
    assert render(lv) =~ "Severe Weather Net"
    # The second viewer sees the rename over PubSub.
    assert render(other_lv) =~ "Severe Weather Net"
  end

  test "cancelling a rename keeps the current name", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    lv |> element("#edit-net-name") |> render_click()
    lv |> element("button", "Cancel") |> render_click()

    refute has_element?(lv, "#net-name-form")
    assert render(lv) =~ session.name
  end

  test "ending a net removes the check-in form", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")
    assert html =~ "checkin-form"

    html = lv |> element("button", "End net") |> render_click()
    refute html =~ "checkin-form"
  end
end

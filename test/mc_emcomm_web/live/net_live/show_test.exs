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

  test "ending a net removes the check-in form", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")
    assert html =~ "checkin-form"

    html = lv |> element("button", "End net") |> render_click()
    refute html =~ "checkin-form"
  end
end

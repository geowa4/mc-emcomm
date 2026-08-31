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

  test "editing a check-in corrects it for other viewers and re-links the member", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    other_member = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    # Mistyped call sign, matching no member.
    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2OTX"}) |> render_submit()

    [checkin] = checkins_for(session.id, "W2OTX")
    assert is_nil(checkin.member_id)

    lv |> element("#edit-checkin-#{checkin.id}") |> render_click()
    assert has_element?(lv, "#edit-checkin-form")

    lv
    |> form("#edit-checkin-form", net_checkin: %{call_sign: "w2oth", notes: "corrected"})
    |> render_submit()

    refute has_element?(lv, "#edit-checkin-form")
    assert render(lv) =~ "W2OTH"
    assert render(lv) =~ "corrected"
    # The correction re-links the member record by call sign.
    [checkin] = checkins_for(session.id, "W2OTH")
    assert checkin.member_id == other_member.id
    # The second viewer receives the correction over PubSub.
    assert render(other_lv) =~ "W2OTH"
  end

  test "leaving logs an end time and checking back in adds a new roster entry", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2OTH"}) |> render_submit()

    [checkin] = checkins_for(session.id, "W2OTH")
    lv |> element("#checkout-checkin-#{checkin.id}") |> render_click()

    [checkin] = checkins_for(session.id, "W2OTH")
    assert checkin.ended_at
    # The ended check-in no longer offers a leave button.
    refute has_element?(lv, "#checkout-checkin-#{checkin.id}")

    # Coming back later is a fresh check-in; the earlier stint stays logged.
    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2OTH"}) |> render_submit()

    checkins = checkins_for(session.id, "W2OTH")
    assert length(checkins) == 2
    assert has_element?(lv, "#checkin-row-#{checkin.id}")
    [returned] = Enum.reject(checkins, &(&1.id == checkin.id))
    assert is_nil(returned.ended_at)
    assert has_element?(lv, "#checkout-checkin-#{returned.id}")
  end

  test "ending the net ends every open check-in", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    other_member = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2NCO"}) |> render_submit()
    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2OTH"}) |> render_submit()

    lv |> element("button", "End net") |> render_click()

    reloaded = McEmcomm.Net.get_session!(session.id)
    assert reloaded.ended_at

    for checkin <- reloaded.checkins do
      assert DateTime.compare(checkin.ended_at, reloaded.ended_at) == :eq
    end

    # Other viewers see the ended net without any leave buttons left.
    refute has_element?(other_lv, "#checkin-form")
    refute render(other_lv) =~ "checkout-checkin-"
  end

  defp checkins_for(session_id, call_sign) do
    for c <- McEmcomm.Net.get_session!(session_id).checkins, c.call_sign == call_sign, do: c
  end
end

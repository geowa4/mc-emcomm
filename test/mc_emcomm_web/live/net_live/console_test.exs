defmodule McEmcommWeb.NetLive.ConsoleTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Net

  test "an approved member can start a named net and is taken to its console", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(conn, member.user)

    {:ok, lv, _html} = live(conn, ~p"/app/net")

    {:ok, show_lv, html} =
      lv
      |> form("#start-net-form", net_session: %{name: "Tuesday Training Net"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Tuesday Training Net"
    assert html =~ "Roster"
    assert has_element?(show_lv, "button", "End net")
  end

  test "the operator calling the net is logged as its first check-in", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    {:ok, _} = McEmcomm.Members.update_profile(member, %{quadrant: :NW})
    conn = log_in_user(conn, member.user)

    {:ok, lv, _html} = live(conn, ~p"/app/net")

    {:ok, show_lv, _html} =
      lv
      |> form("#start-net-form", net_session: %{name: "Tuesday Training Net"})
      |> render_submit()
      |> follow_redirect(conn)

    assert render(show_lv) =~ "W2NCO"

    [session] = Net.list_sessions()
    [checkin] = Net.get_session!(session.id).checkins
    assert checkin.call_sign == "W2NCO"
    assert checkin.member_id == member.id
    assert checkin.quadrant == :NW
    assert is_nil(checkin.ended_at)
  end

  test "a starter without a call sign is not auto-checked-in" do
    member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    assert Net.get_session!(session.id).checkins == []
  end

  test "starting a net with a blank name defaults the name to the date", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(conn, member.user)

    {:ok, lv, _html} = live(conn, ~p"/app/net")

    {:ok, _show_lv, html} =
      lv
      |> form("#start-net-form", net_session: %{name: ""})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ Date.to_string(Date.utc_today())
  end

  test "lists active and past net sessions", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)
    {:ok, _} = Net.end_session(session)

    {:ok, _lv, html} = conn |> log_in_user(member.user) |> live(~p"/app/net")

    assert html =~ session.name
    assert html =~ "Past nets"
  end
end

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

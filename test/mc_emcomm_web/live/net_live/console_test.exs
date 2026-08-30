defmodule McEmcommWeb.NetLive.ConsoleTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Net

  test "an approved member can start a net and is taken to its console", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(conn, member.user)

    {:ok, lv, _html} = live(conn, ~p"/app/net")

    {:ok, show_lv, html} =
      lv |> element("button", "Start new net") |> render_click() |> follow_redirect(conn)

    assert html =~ "Roster"
    assert has_element?(show_lv, "button", "End net")
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

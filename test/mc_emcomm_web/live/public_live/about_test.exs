defmodule McEmcommWeb.PublicLive.AboutTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "renders without leadership when none is set", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/about")

    assert html =~ "About Monroe County EmComm"
    assert html =~ "Leadership roster coming soon"
  end

  test "renders leadership from members with a non-member role", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{name: "Riley Officer", call_sign: "W2LDR"})
    McEmcomm.Members.update_role(member, %{role: :secretary})

    {:ok, _lv, html} = live(conn, ~p"/about")

    assert html =~ "Riley Officer"
    assert html =~ "W2LDR"
    assert html =~ "Secretary"
  end
end

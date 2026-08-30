defmodule McEmcommWeb.AppLive.DashboardTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "renders links to the member portal sections", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()

    {:ok, _lv, html} = conn |> log_in_user(member.user) |> live(~p"/app")

    assert html =~ "Member Portal"
    assert html =~ "My Profile"
    assert html =~ "Net Console"
  end
end

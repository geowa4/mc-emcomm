defmodule McEmcommWeb.AdminLive.DashboardTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "shows a pending-members badge when there are pending members", %{conn: conn} do
    McEmcommFixtures.pending_member_fixture()
    scope = McEmcommFixtures.admin_scope_fixture()

    {:ok, _lv, html} = conn |> log_in_user(scope.user) |> live(~p"/admin")

    assert html =~ "1 pending"
  end
end

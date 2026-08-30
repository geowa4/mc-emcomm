defmodule MyAppWeb.LiveDashboardTest do
  use MyAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "requires a logged-in user", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/dev/dashboard")
    assert to == ~p"/users/log-in"
  end

  test "renders the dashboard for a logged-in user", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    {:ok, lv, _html} =
      conn
      |> live(~p"/dev/dashboard")
      |> follow_redirect(conn, ~p"/dev/dashboard/home")

    assert has_element?(lv, "#menu-bar")
  end
end

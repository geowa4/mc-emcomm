defmodule McEmcommWeb.LayoutsTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  describe "keyboard and screen-reader structure" do
    test "offers a skip link that lands on the main landmark", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "a#skip-to-content[href='#main-content']")
      assert has_element?(lv, "main#main-content[tabindex='-1']")
    end

    test "wraps the site navigation in a labelled nav landmark", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "nav[aria-label='Main'] #nav-home")
      assert has_element?(lv, "nav[aria-label='Main'] #mobile-menu")
    end

    test "the menus are native disclosures with named toggles", %{conn: conn} do
      scope = McEmcommFixtures.admin_scope_fixture()
      {:ok, lv, _html} = conn |> log_in_user(scope.user) |> live(~p"/about")

      assert has_element?(lv, "details#user-menu > summary#user-menu-button")
      assert has_element?(lv, "details#user-menu #user-menu-log-out")

      assert has_element?(
               lv,
               "details#mobile-menu > summary#mobile-menu-button[aria-label='Menu']"
             )
    end

    test "the theme toggle is a labelled group of named buttons", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "#theme-toggle[role='group'][aria-label='Color theme']")
      assert has_element?(lv, "#theme-toggle button[data-phx-theme='system'][aria-label]")
      assert has_element?(lv, "#theme-toggle button[data-phx-theme='light'][aria-label]")
      assert has_element?(lv, "#theme-toggle button[data-phx-theme='dark'][aria-label]")
      assert has_element?(lv, "#mobile-theme-toggle[role='group']")
    end

    test "external footer links announce that they open a new tab", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "#site-footer a[target='_blank'] .sr-only", "opens in a new tab")
    end

    test "an active net is described in text on the brand link, not only by glow", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(member, %{"name" => "Tuesday Net"})

      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "#header-brand .sr-only", "Tuesday Net is on the air")
      assert session.name == "Tuesday Net"
    end
  end
end

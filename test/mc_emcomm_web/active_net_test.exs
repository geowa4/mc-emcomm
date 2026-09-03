defmodule McEmcommWeb.ActiveNetTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Net

  describe "header emblem" do
    test "is unlit when no net is active", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "#header-emblem")
      refute has_element?(lv, "#header-emblem[data-active-net]")
    end

    test "is lit on a live page while a net is on the air", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      McEmcommFixtures.net_session_fixture(member)

      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "#header-emblem[data-active-net]")
    end

    test "lights up and goes dark as nets start and end", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      {:ok, lv, _html} = live(conn, ~p"/about")

      refute has_element?(lv, "#header-emblem[data-active-net]")

      session = McEmcommFixtures.net_session_fixture(member)
      assert has_element?(lv, "#header-emblem[data-active-net]")

      {:ok, _ended} = Net.end_session(session)
      refute has_element?(lv, "#header-emblem[data-active-net]")
    end

    test "is lit on the controller-rendered home page", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      McEmcommFixtures.net_session_fixture(member)

      html = conn |> get(~p"/") |> html_response(200)

      emblem =
        html |> LazyHTML.from_document() |> LazyHTML.query("#header-emblem[data-active-net]")

      refute Enum.empty?(emblem)
    end
  end
end

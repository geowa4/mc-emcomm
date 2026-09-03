defmodule McEmcommWeb.ActiveNetTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.AccountsFixtures
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

    test "names the net in its tooltip", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      McEmcommFixtures.net_session_fixture(member, %{"name" => "Tuesday Net"})

      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "#header-emblem[title='Tuesday Net is on the air']")
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

  describe "brand link" do
    test "goes home when no net is active", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      conn = log_in_user(conn, member.user)

      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "#header-brand[href='/']")
    end

    test "takes a member to the most recent active net", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      conn = log_in_user(conn, member.user)
      {:ok, lv, _html} = live(conn, ~p"/about")

      assert has_element?(lv, "#header-brand[href='/']")

      older = McEmcommFixtures.net_session_fixture(member)
      assert has_element?(lv, "#header-brand[href='/app/net/#{older.id}']")

      newer = McEmcommFixtures.net_session_fixture(member)
      assert has_element?(lv, "#header-brand[href='/app/net/#{newer.id}']")

      {:ok, _} = Net.end_session(newer)
      assert has_element?(lv, "#header-brand[href='/app/net/#{older.id}']")

      {:ok, _} = Net.end_session(older)
      assert has_element?(lv, "#header-brand[href='/']")
    end

    test "sends a visitor to log in and back to the net afterwards", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      user = AccountsFixtures.set_password(member.user)
      session = McEmcommFixtures.net_session_fixture(member)

      {:ok, lv, _html} = live(conn, ~p"/about")
      assert has_element?(lv, "#header-brand[href='/app/net/#{session.id}']")

      conn = get(conn, ~p"/app/net/#{session.id}")
      assert redirected_to(conn) == ~p"/users/log-in"

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => AccountsFixtures.valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/app/net/#{session.id}"
    end
  end

  test "the nav has a Home link", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/about")

    assert has_element?(lv, "#nav-home[href='/']")
    assert has_element?(lv, "#mobile-nav-home[href='/']")
  end
end

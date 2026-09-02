defmodule McEmcommWeb.NetLive.AprsTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Net

  describe "starting a net" do
    test "requires an APRS keyword", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      conn = log_in_user(conn, member.user)

      {:ok, lv, _html} = live(conn, ~p"/app/net")
      assert has_element?(lv, "#start-net-aprs-keyword")

      lv
      |> form("#start-net-form", net_session: %{name: "Keyless", aprs_keyword: ""})
      |> render_submit()

      assert has_element?(lv, "#start-net-form p.text-error")
      assert Net.list_active_sessions() == []
    end

    test "rejects a keyword another active net is using", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      other = McEmcommFixtures.net_session_fixture(member)
      conn = log_in_user(conn, member.user)

      {:ok, lv, _html} = live(conn, ~p"/app/net")

      lv
      |> form("#start-net-form",
        net_session: %{name: "Clash", aprs_keyword: String.downcase(other.aprs_keyword)}
      )
      |> render_submit()

      assert has_element?(lv, "#start-net-form p.text-error", "already used by an active net")
      assert [%{id: id}] = Net.list_active_sessions()
      assert id == other.id
    end
  end

  describe "on the net page" do
    test "shows the keyword and lets it be changed for every viewer", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(member)
      conn = log_in_user(conn, member.user)

      {:ok, lv, _html} = live(conn, ~p"/app/net/#{session.id}")
      {:ok, viewer, _html} = live(conn, ~p"/app/net/#{session.id}")
      assert has_element?(lv, "#net-aprs-keyword", session.aprs_keyword)

      lv |> element("#edit-net-aprs-keyword") |> render_click()

      lv
      |> form("#net-aprs-keyword-form", net_session: %{aprs_keyword: "two words"})
      |> render_submit()

      assert has_element?(lv, "#net-aprs-keyword-form p.text-error")

      keyword = McEmcommFixtures.unique_aprs_keyword()

      lv
      |> form("#net-aprs-keyword-form", net_session: %{aprs_keyword: keyword})
      |> render_submit()

      refute has_element?(lv, "#net-aprs-keyword-form")
      assert has_element?(lv, "#net-aprs-keyword", keyword)
      assert has_element?(viewer, "#net-aprs-keyword", keyword)
    end

    test "the keyword is read-only once the net has ended", %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(member)
      {:ok, _ended} = Net.end_session(session)
      conn = log_in_user(conn, member.user)

      {:ok, lv, _html} = live(conn, ~p"/app/net/#{session.id}")

      assert has_element?(lv, "#net-aprs-keyword", session.aprs_keyword)
      refute has_element?(lv, "#edit-net-aprs-keyword")
    end

    test "an APRS check-in joins the roster and the map, and its pin follows the station",
         %{conn: conn} do
      member = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(member)
      conn = log_in_user(conn, member.user)

      {:ok, lv, _html} = live(conn, ~p"/app/net/#{session.id}")

      {:ok, [checkin]} =
        Net.record_aprs_position(
          McEmcommFixtures.aprs_position_fixture(%{
            comment: "qrv #{session.aprs_keyword}",
            point: McEmcommFixtures.geo_point(-77.5, 43.2)
          })
        )

      assert has_element?(lv, "#checkin-row-#{checkin.id}", "W2XYZ")
      assert has_element?(lv, "#checkin-aprs-#{checkin.id}", "W2XYZ-9")
      assert has_element?(lv, "#net-map[data-markers*='W2XYZ']")
      assert has_element?(lv, "#net-map[data-markers*='43.2']")

      {:ok, [_moved]} =
        Net.record_aprs_position(
          McEmcommFixtures.aprs_position_fixture(%{
            comment: "",
            point: McEmcommFixtures.geo_point(-77.6, 43.3)
          })
        )

      assert has_element?(lv, "#net-map[data-markers*='43.3']")
      refute has_element?(lv, "#net-map[data-markers*='43.2']")
      assert has_element?(lv, "#checkin-aprs-#{checkin.id}")
    end
  end
end

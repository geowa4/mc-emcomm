defmodule McEmcommWeb.AppLive.ProfileTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.Capabilities
  alias McEmcomm.Certifications
  alias McEmcomm.Courses
  alias McEmcomm.McEmcommFixtures

  test "redirects a logged-in user with no member profile", %{conn: conn} do
    user = McEmcomm.AccountsFixtures.user_fixture()
    assert {:error, {:redirect, %{to: "/"}}} = conn |> log_in_user(user) |> live(~p"/app")
  end

  test "updates profile fields", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(conn, member.user)
    {:ok, lv, _html} = live(conn, ~p"/app/profile")

    html =
      lv
      |> form("#profile-form",
        member: %{name: "New Name", call_sign: "w2new", license_class: "general", quadrant: "SE"}
      )
      |> render_submit()

    assert html =~ "Profile updated"
    assert html =~ "New Name"
    assert html =~ "W2NEW"
  end

  test "dropping a pin persists the QTH point", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(conn, member.user)
    {:ok, lv, _html} = live(conn, ~p"/app/profile")

    render_hook(lv, "point_selected", %{"lat" => 43.15, "lng" => -77.6})

    updated = McEmcomm.Members.get_member!(member.id)
    assert %Geo.Point{} = updated.qth_point
  end

  test "toggling a capability adds and removes it", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    capability = McEmcommFixtures.capability_fixture(%{name: "APRS"})
    conn = log_in_user(conn, member.user)
    {:ok, lv, _html} = live(conn, ~p"/app/profile")

    lv |> element("input[phx-value-id='#{capability.id}']") |> render_click()
    assert [%{capability_id: cap_id}] = Capabilities.list_member_capabilities(member.id)
    assert cap_id == capability.id

    lv |> element("input[phx-value-id='#{capability.id}']") |> render_click()
    assert Capabilities.list_member_capabilities(member.id) == []
  end

  test "an event naming a course the page never rendered is ignored", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(conn, member.user)
    {:ok, lv, _html} = live(conn, ~p"/app/profile")

    # The id is interpolated into the per-record upload name, so an unknown one
    # would mint an atom and then raise on the missing upload config.
    render_submit(lv, "save_course", %{"course_id" => "987654321"})
    render_submit(lv, "save_course", %{"course_id" => "../../etc"})

    assert Courses.list_member_courses(member.id) == []
  end

  test "saving a course records completion", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    course = McEmcommFixtures.course_fixture(%{name: "IS-100"})
    conn = log_in_user(conn, member.user)
    {:ok, lv, _html} = live(conn, ~p"/app/profile")

    html =
      lv
      |> element("form[phx-value-course_id='#{course.id}']")
      |> render_submit(%{"completed_on" => "2026-01-15"})

    assert html =~ "Completed 2026-01-15"
    assert [mc] = Courses.list_member_courses(member.id)
    assert mc.completed_on == ~D[2026-01-15]
  end

  test "saving a certification records the issue date and shows the prerequisite status", %{
    conn: conn
  } do
    prereq_course = McEmcommFixtures.course_fixture(%{name: "AUXCOMM"})

    certification =
      McEmcommFixtures.certification_fixture(%{
        name: "AUXC",
        prerequisite_course_id: prereq_course.id
      })

    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(conn, member.user)
    {:ok, lv, html} = live(conn, ~p"/app/profile")

    assert html =~ "not yet"

    html =
      lv
      |> element("form[phx-value-certification_id='#{certification.id}']")
      |> render_submit(%{"issued_on" => "2026-02-01"})

    assert [mc] = Certifications.list_member_certifications(member.id)
    assert mc.issued_on == ~D[2026-02-01]
    refute html =~ "Certification error"
  end
end

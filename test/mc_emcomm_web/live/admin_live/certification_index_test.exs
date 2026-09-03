defmodule McEmcommWeb.AdminLive.CertificationIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.Certifications
  alias McEmcomm.McEmcommFixtures

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "creating a certification with a prerequisite course, then editing and deleting it", %{
    conn: conn
  } do
    course = McEmcommFixtures.course_fixture(%{name: "AUXCOMM"})
    {:ok, lv, _html} = live(conn, ~p"/admin/certifications")

    lv |> element("button", "New certification") |> render_click()

    html =
      lv
      |> form("#certification-form",
        certification: %{
          name: "AUXC",
          prerequisite_course_id: course.id,
          requires_task_book: "true"
        }
      )
      |> render_submit()

    assert html =~ "AUXC"
    assert html =~ "AUXCOMM"

    certification = Enum.find(Certifications.list_certifications(), &(&1.name == "AUXC"))
    assert certification.prerequisite_course_id == course.id

    lv |> element("button", "Edit") |> render_click()
    lv |> form("#certification-form", certification: %{name: "AUXC Renewed"}) |> render_submit()
    assert Certifications.get_certification!(certification.id).name == "AUXC Renewed"

    lv |> element("button", "Delete") |> render_click()
    assert Certifications.list_certifications() == []
  end
end

defmodule McEmcommWeb.AdminLive.CourseIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.Courses
  alias McEmcomm.McEmcommFixtures

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "creating, editing, and deleting a course", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/courses")

    lv |> element("button", "New course") |> render_click()

    html =
      lv |> form("#course-form", course: %{name: "IS-100", code: "IS-100"}) |> render_submit()

    assert html =~ "IS-100"

    course = Enum.find(Courses.list_courses(), &(&1.name == "IS-100"))

    lv |> element("a", "Edit") |> render_click()
    lv |> form("#course-form", course: %{name: "IS-100.C"}) |> render_submit()
    assert Courses.get_course!(course.id).name == "IS-100.C"

    lv |> element("a", "Delete") |> render_click()
    assert Courses.list_courses() == []
  end
end

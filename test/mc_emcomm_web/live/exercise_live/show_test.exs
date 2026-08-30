defmodule McEmcommWeb.ExerciseLive.ShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias McEmcomm.Exercises
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  test "renders locations, attachments, and attendance", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    exercise = McEmcommFixtures.exercise_fixture()

    {:ok, lv, html} = conn |> log_in_user(member.user) |> live(~p"/app/exercises/#{exercise.id}")

    assert html =~ exercise.title
    assert html =~ "Primary Site"
    assert html =~ "No attachments"
    assert html =~ "No recorded attendance yet"
    assert has_element?(lv, "button", "Mark my attendance")
  end

  test "an approved member can mark their own attendance", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    exercise = McEmcommFixtures.exercise_fixture()

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/exercises/#{exercise.id}")

    html = lv |> element("button", "Mark my attendance") |> render_click()

    assert html =~ "Attendance recorded"
    assert [attendance] = Exercises.list_attendance(exercise.id)
    assert attendance.member_id == member.id
    assert attendance.source == :manual
  end

  test "a download event carrying a junk id is declined, not crashed on", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    exercise = McEmcommFixtures.exercise_fixture()

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/exercises/#{exercise.id}")

    assert render_click(lv, "download_attachment", %{"id" => "not-an-id"}) =~
             "no longer available"
  end

  test "downloading an attachment redirects to a presigned URL", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    exercise = McEmcommFixtures.exercise_fixture()

    {:ok, attachment} =
      Exercises.create_exercise_attachment(%{
        exercise_id: exercise.id,
        key: "exercise-attachments/plan.pdf",
        filename: "plan.pdf",
        content_type: "application/pdf",
        description: "Operations plan",
        uploaded_by_id: member.user_id
      })

    expect(StorageMock, :presign_download_url, fn key ->
      assert key == attachment.key
      "https://tigris.example.com/plan.pdf?signed=1"
    end)

    {:ok, lv, html} = conn |> log_in_user(member.user) |> live(~p"/app/exercises/#{exercise.id}")
    assert html =~ "Operations plan"

    assert {:error, {:redirect, %{to: "https://tigris.example.com/plan.pdf?signed=1"}}} =
             lv |> element("button", "Download") |> render_click()
  end
end

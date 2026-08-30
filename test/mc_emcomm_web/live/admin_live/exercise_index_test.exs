defmodule McEmcommWeb.AdminLive.ExerciseIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias McEmcomm.Exercises
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "lists exercises", %{conn: conn} do
    McEmcommFixtures.exercise_fixture(%{"title" => "Field Day"})
    {:ok, _lv, html} = live(conn, ~p"/admin/exercises")
    assert html =~ "Field Day"
  end

  test "creating a new exercise", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/exercises/new")

    {:ok, edit_lv, html} =
      lv
      |> form("#exercise-form",
        exercise: %{
          title: "New Exercise",
          starts_at: "2026-09-01T10:00",
          ends_at: "2026-09-01T14:00",
          visibility: "public"
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Exercise created"
    assert has_element?(edit_lv, "#exercise-form")
    assert Enum.any?(Exercises.list_exercises(), &(&1.title == "New Exercise"))
  end

  test "adding and removing a location via the map picker", %{conn: conn} do
    exercise = McEmcommFixtures.exercise_fixture(%{"title" => "Multi Site"}, %{"name" => "HQ"})
    {:ok, lv, _html} = live(conn, ~p"/admin/exercises/#{exercise.id}/edit")

    render_hook(lv, "point_selected", %{"lat" => 43.2, "lng" => -77.5})

    html =
      lv
      |> form("#location-form",
        exercise_location: %{name: "Repeater Site", geofence_radius_m: 250}
      )
      |> render_submit()

    assert html =~ "Repeater Site"
    reloaded = Exercises.get_exercise!(exercise.id)
    assert Enum.count(reloaded.locations) == 2

    new_location = Enum.find(reloaded.locations, &(&1.name == "Repeater Site"))

    html =
      lv
      |> element("a[phx-value-id='#{new_location.id}']", "Remove")
      |> render_click()

    refute html =~ "Repeater Site"
    assert Enum.count(Exercises.get_exercise!(exercise.id).locations) == 1
  end

  test "a single location added with a blank name defaults to Primary Site", %{conn: conn} do
    creator = McEmcomm.AccountsFixtures.user_fixture()

    {:ok, exercise} =
      Exercises.create_exercise(%{
        "title" => "Single Site",
        "starts_at" => DateTime.utc_now(),
        "ends_at" => DateTime.add(DateTime.utc_now(), 3600, :second),
        "visibility" => "members",
        "created_by_id" => creator.id
      })

    {:ok, lv, _html} = live(conn, ~p"/admin/exercises/#{exercise.id}/edit")

    render_hook(lv, "point_selected", %{"lat" => 43.2, "lng" => -77.5})

    lv
    |> form("#location-form", exercise_location: %{name: "", geofence_radius_m: 500})
    |> render_submit()

    assert [%{name: "Primary Site"}] = Exercises.get_exercise!(exercise.id).locations
  end

  test "uploading an attachment with a description", %{conn: conn} do
    exercise = McEmcommFixtures.exercise_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/exercises/#{exercise.id}/edit")

    expect(StorageMock, :presign_upload, fn key, "text/plain" ->
      %{url: "https://tigris.example.com/upload", fields: %{"key" => key}}
    end)

    file =
      file_input(lv, "#attachment-form", :attachment, [
        %{name: "plan.txt", content: "the plan", type: "text/plain"}
      ])

    render_upload(file, "plan.txt")

    html =
      lv
      |> element("#attachment-form")
      |> render_submit(%{description: "Operations plan"})

    assert html =~ "Operations plan"
    assert html =~ "plan.txt"
  end

  test "deleting an exercise", %{conn: conn} do
    exercise = McEmcommFixtures.exercise_fixture(%{"title" => "To Delete"})
    {:ok, lv, _html} = live(conn, ~p"/admin/exercises")

    lv |> element("a[phx-value-id='#{exercise.id}']", "Delete") |> render_click()

    refute Enum.any?(Exercises.list_exercises(), &(&1.id == exercise.id))
  end
end

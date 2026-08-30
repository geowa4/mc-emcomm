defmodule McEmcommWeb.ExerciseLive.PublicShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "shows a public exercise's summary", %{conn: conn} do
    exercise =
      McEmcommFixtures.exercise_fixture(%{
        "title" => "Open Drill",
        "description" => "Come one come all",
        "visibility" => "public"
      })

    {:ok, _lv, html} = live(conn, ~p"/exercises/#{exercise.id}")

    assert html =~ "Open Drill"
    assert html =~ "Come one come all"
  end

  test "redirects away from a members-only exercise", %{conn: conn} do
    exercise = McEmcommFixtures.exercise_fixture(%{"visibility" => "members"})

    assert {:error, {:live_redirect, %{to: "/exercises"}}} =
             live(conn, ~p"/exercises/#{exercise.id}")
  end

  test "redirects away from a nonexistent exercise", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/exercises"}}} = live(conn, ~p"/exercises/999999")
  end
end

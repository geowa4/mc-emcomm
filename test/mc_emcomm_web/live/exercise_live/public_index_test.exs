defmodule McEmcommWeb.ExerciseLive.PublicIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "lists only public-visibility exercises", %{conn: conn} do
    public =
      McEmcommFixtures.exercise_fixture(%{"title" => "Open Drill", "visibility" => "public"})

    McEmcommFixtures.exercise_fixture(%{
      "title" => "Members Only Drill",
      "visibility" => "members"
    })

    {:ok, _lv, html} = live(conn, ~p"/exercises")

    assert html =~ public.title
    refute html =~ "Members Only Drill"
  end

  test "renders empty state with no public exercises", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/exercises")
    assert html =~ "No upcoming public exercises"
  end
end

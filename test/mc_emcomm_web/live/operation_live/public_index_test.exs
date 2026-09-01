defmodule McEmcommWeb.OperationLive.PublicIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "lists only public-visibility operations", %{conn: conn} do
    public =
      McEmcommFixtures.operation_fixture(%{"title" => "Open Drill", "visibility" => "public"})

    McEmcommFixtures.operation_fixture(%{
      "title" => "Members Only Drill",
      "visibility" => "members"
    })

    {:ok, _lv, html} = live(conn, ~p"/operations")

    assert html =~ public.title
    refute html =~ "Members Only Drill"
  end

  test "renders empty state with no public operations", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/operations")
    assert html =~ "No upcoming public operations"
  end
end

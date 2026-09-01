defmodule McEmcommWeb.OperationLive.PublicShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "shows a public operation's summary", %{conn: conn} do
    operation =
      McEmcommFixtures.operation_fixture(%{
        "title" => "Open Drill",
        "description" => "Come one come all",
        "visibility" => "public"
      })

    {:ok, _lv, html} = live(conn, ~p"/operations/#{operation.id}")

    assert html =~ "Open Drill"
    assert html =~ "Come one come all"
  end

  test "redirects away from a members-only operation", %{conn: conn} do
    operation = McEmcommFixtures.operation_fixture(%{"visibility" => "members"})

    assert {:error, {:live_redirect, %{to: "/operations"}}} =
             live(conn, ~p"/operations/#{operation.id}")
  end

  test "redirects away from a nonexistent operation", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/operations"}}} = live(conn, ~p"/operations/999999")
  end
end

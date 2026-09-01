defmodule McEmcommWeb.OperationLive.IndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "an approved member sees operations of every visibility", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()

    public =
      McEmcommFixtures.operation_fixture(%{"title" => "Public One", "visibility" => "public"})

    members_only =
      McEmcommFixtures.operation_fixture(%{"title" => "Members One", "visibility" => "members"})

    {:ok, _lv, html} = conn |> log_in_user(member.user) |> live(~p"/app/operations")

    assert html =~ public.title
    assert html =~ members_only.title
  end
end

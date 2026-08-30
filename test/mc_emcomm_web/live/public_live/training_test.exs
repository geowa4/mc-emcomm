defmodule McEmcommWeb.PublicLive.TrainingTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the FEMA course list", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/training")

    assert html =~ "Training"
    assert html =~ "IS-100.C"
    assert html =~ "AuxComm Training"
    assert html =~ "secretary@monroecountyemcomm.org"
  end

  test "only logged-in visitors see the member profile link", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/training")
    refute html =~ "/app/profile"

    member = McEmcomm.McEmcommFixtures.member_fixture()
    {:ok, _lv, html} = conn |> log_in_user(member.user) |> live(~p"/training")
    assert html =~ "/app/profile"
  end
end

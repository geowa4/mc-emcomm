defmodule McEmcommWeb.PublicLive.TrainingTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the FEMA course list", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/training")

    assert html =~ "Training"
    assert html =~ "IS-100.C"
    assert html =~ "AuxComm Training"
  end
end

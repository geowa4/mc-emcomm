defmodule McEmcommWeb.PublicLive.DonationsTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the donation options", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/donations")

    assert html =~ "Support Monroe County EmComm"
    assert html =~ "Donate online via Zeffy"
  end
end

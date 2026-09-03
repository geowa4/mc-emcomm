defmodule McEmcommWeb.InventoryLive.IndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "lists assets with a link to their detail page", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    asset = McEmcommFixtures.asset_fixture(%{name: "Field Go-Kit"})

    {:ok, _lv, html} = conn |> log_in_user(member.user) |> live(~p"/app/inventory")

    assert html =~ "Field Go-Kit"
    assert html =~ asset.public_id
  end

  test "each asset's name is a real link, so the row works from the keyboard", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    asset = McEmcommFixtures.asset_fixture(%{name: "Field Go-Kit"})

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/inventory")

    assert has_element?(lv, "#assets a[href='/app/inventory/#{asset.public_id}']", "Field Go-Kit")
  end
end

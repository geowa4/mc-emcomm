defmodule McEmcommWeb.AdminLive.InventoryIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias McEmcomm.Assets
  alias McEmcomm.McEmcommFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "creating an asset auto-generates a public_id", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/inventory")

    lv |> element("button", "New asset") |> render_click()

    html =
      lv
      |> form("#asset-form", asset: %{name: "Field Go-Kit", description: "Backpack radio kit"})
      |> render_submit()

    assert html =~ "Field Go-Kit"
    assert [asset] = Assets.list_assets()
    assert String.length(asset.public_id) == 6
  end

  test "shows the QR code encoding the sighting URL", %{conn: conn} do
    asset = McEmcommFixtures.asset_fixture(%{name: "Repeater Trailer"})
    {:ok, lv, _html} = live(conn, ~p"/admin/inventory")

    html = lv |> element("button", "QR code") |> render_click()

    assert html =~ "QR code &mdash; Repeater Trailer" or html =~ "Repeater Trailer"
    assert html =~ "/a/#{asset.public_id}/s"
    assert html =~ "<svg"
  end

  test "editing an asset", %{conn: conn} do
    asset = McEmcommFixtures.asset_fixture(%{name: "Old Name"})
    {:ok, lv, _html} = live(conn, ~p"/admin/inventory")

    lv |> element("button", "Edit") |> render_click()
    lv |> form("#asset-form", asset: %{name: "New Name"}) |> render_submit()

    assert Assets.get_asset!(asset.id).name == "New Name"
  end

  test "deleting an asset", %{conn: conn} do
    McEmcommFixtures.asset_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/inventory")

    lv |> element("button", "Delete") |> render_click()

    assert Assets.list_assets() == []
  end
end

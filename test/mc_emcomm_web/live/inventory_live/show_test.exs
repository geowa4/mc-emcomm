defmodule McEmcommWeb.InventoryLive.ShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Sightings

  setup do
    asset = McEmcommFixtures.asset_fixture(%{name: "Field Go-Kit"})

    {:ok, sighting} =
      Sightings.record_visit(%{
        asset_id: asset.id,
        session_token: "tok",
        visited_at: DateTime.utc_now(),
        remote_ip: "203.0.113.5",
        user_agent: "SecretAgent/1.0"
      })

    {:ok, _sighting} = Sightings.submit(sighting, %{"call_sign" => "W2SEE", "note" => "spotted"})

    %{asset: asset}
  end

  test "a member sees the submission log but no map and no admin-only columns", %{
    conn: conn,
    asset: asset
  } do
    member = McEmcommFixtures.member_fixture()

    {:ok, _lv, html} =
      conn |> log_in_user(member.user) |> live(~p"/app/inventory/#{asset.public_id}")

    assert html =~ "Recent activity"
    assert html =~ "W2SEE"
    refute html =~ "Sighting map"
    refute html =~ "203.0.113.5"
    refute html =~ "SecretAgent"
  end

  test "an admin sees the full sighting log, map, and admin-only columns", %{
    conn: conn,
    asset: asset
  } do
    scope = McEmcommFixtures.admin_scope_fixture()

    {:ok, _lv, html} =
      conn |> log_in_user(scope.user) |> live(~p"/app/inventory/#{asset.public_id}")

    assert html =~ "Sighting log"
    assert html =~ "Sighting map"
    assert html =~ "W2SEE"
    assert html =~ "203.0.113.5"
  end

  test "redirects for an unknown public_id", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()

    assert {:error, {:live_redirect, %{to: "/app/inventory"}}} =
             conn |> log_in_user(member.user) |> live(~p"/app/inventory/ZZZZZZ")
  end
end

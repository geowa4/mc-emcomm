defmodule McEmcommWeb.Plugs.RecordSightingTest do
  use McEmcommWeb.ConnCase, async: true

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Sightings

  @googlebot "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
  @phone "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " <>
           "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

  test "a visitor's scan records a sighting", %{conn: conn} do
    asset = McEmcommFixtures.asset_fixture()

    conn =
      conn
      |> put_req_header("user-agent", @phone)
      |> get(~p"/a/#{asset.public_id}/s")

    assert html_response(conn, 200)
    assert [_sighting] = Sightings.list_for_asset_admin_view(asset.id)
  end

  test "a crawler's visit records nothing and is sent home", %{conn: conn} do
    asset = McEmcommFixtures.asset_fixture()

    conn =
      conn
      |> put_req_header("user-agent", @googlebot)
      |> get(~p"/a/#{asset.public_id}/s")

    assert redirected_to(conn) == ~p"/"
    assert Sightings.list_for_asset_admin_view(asset.id) == []
  end
end

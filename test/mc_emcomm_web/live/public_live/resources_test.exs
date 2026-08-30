defmodule McEmcommWeb.PublicLive.ResourcesTest do
  use McEmcommWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  test "anonymous visitors see members-only documents gated, not downloadable", %{conn: conn} do
    McEmcommFixtures.document_fixture(%{title: "Public Doc", members_only: false})
    McEmcommFixtures.document_fixture(%{title: "Members Doc", members_only: true})

    {:ok, lv, html} = live(conn, ~p"/resources")

    assert html =~ "Public Doc"
    assert html =~ "Members Doc"
    assert html =~ "Log in"
    assert lv |> element("button", "Download") |> has_element?()
  end

  test "anonymous download attempt on a members-only document is refused", %{conn: conn} do
    document = McEmcommFixtures.document_fixture(%{members_only: true})
    {:ok, lv, _html} = live(conn, ~p"/resources")

    html = lv |> render_click("download", %{"id" => to_string(document.id)})

    assert html =~ "Log in as an approved member"
  end

  test "an approved member can download a members-only document", %{conn: conn} do
    document = McEmcommFixtures.document_fixture(%{members_only: true})
    member = McEmcommFixtures.member_fixture()

    expect(StorageMock, :presign_download_url, fn key ->
      assert key == document.key
      "https://tigris.example.com/#{key}?signed=1"
    end)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/resources")

    assert {:error, {:redirect, %{to: "https://tigris.example.com/" <> _}}} =
             lv |> render_click("download", %{"id" => to_string(document.id)})
  end
end

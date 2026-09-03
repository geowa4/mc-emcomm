defmodule McEmcommWeb.AdminLive.DocumentIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias McEmcomm.Content
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "uploading a document, then toggling active and deleting it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/documents")

    expect(StorageMock, :presign_upload, fn key, _content_type ->
      %{url: "https://tigris.example.com/upload", fields: %{"key" => key}}
    end)

    file =
      file_input(lv, "#document-form", :file, [
        %{name: "net-script.pdf", content: "script contents", type: "application/pdf"}
      ])

    render_upload(file, "net-script.pdf")

    html =
      lv
      |> element("#document-form")
      |> render_submit(%{"title" => "Net Control Script"})

    assert html =~ "Net Control Script"
    assert [document] = Content.list_documents(members_only_allowed: true)
    assert document.filename == "net-script.pdf"
    assert document.members_only == true

    html = lv |> element("button", "Deactivate") |> render_click()
    assert Content.get_document!(document.id).active == false
    assert html =~ "Activate"

    lv |> element("button", "Delete") |> render_click()
    assert Content.list_documents(members_only_allowed: true) == []
  end
end

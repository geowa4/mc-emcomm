defmodule McEmcommWeb.AdminLive.OperationIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Operations
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "lists operations", %{conn: conn} do
    McEmcommFixtures.operation_fixture(%{"title" => "Field Day"})
    {:ok, _lv, html} = live(conn, ~p"/admin/operations")
    assert html =~ "Field Day"
  end

  test "creating a new operation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/operations/new")

    {:ok, edit_lv, html} =
      lv
      |> form("#operation-form",
        operation: %{
          title: "New Operation",
          starts_at: "2026-09-01T10:00",
          ends_at: "2026-09-01T14:00",
          visibility: "public"
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Operation created"
    assert has_element?(edit_lv, "#operation-form")
    assert Enum.any?(Operations.list_operations(), &(&1.title == "New Operation"))
  end

  test "adding a location from typed coordinates", %{conn: conn} do
    operation = McEmcommFixtures.operation_fixture(%{"title" => "Typed Site"}, %{"name" => "HQ"})
    {:ok, lv, _html} = live(conn, ~p"/admin/operations/#{operation.id}/edit")

    lv
    |> form("#location-map-coordinates", %{"lat" => "43.2", "lng" => "-77.5"})
    |> render_submit()

    assert_push_event(lv, "picker:set_point", %{id: "location-map", lat: 43.2, lng: -77.5})
    assert has_element?(lv, "#location-pending-point", "43.2")

    lv
    |> form("#location-form", operation_location: %{name: "Typed", geofence_radius_m: 100})
    |> render_submit()

    typed = Enum.find(Operations.get_operation!(operation.id).locations, &(&1.name == "Typed"))
    assert typed.point.coordinates == {-77.5, 43.2}
  end

  test "operations are reachable by a link as well as a row click", %{conn: conn} do
    operation = McEmcommFixtures.operation_fixture(%{"title" => "Field Day"})
    {:ok, lv, _html} = live(conn, ~p"/admin/operations")

    assert has_element?(
             lv,
             "#operations a[href='/admin/operations/#{operation.id}/edit']",
             "Field Day"
           )
  end

  test "adding and removing a location via the map picker", %{conn: conn} do
    operation = McEmcommFixtures.operation_fixture(%{"title" => "Multi Site"}, %{"name" => "HQ"})
    {:ok, lv, _html} = live(conn, ~p"/admin/operations/#{operation.id}/edit")

    render_hook(lv, "point_selected", %{"lat" => 43.2, "lng" => -77.5})

    html =
      lv
      |> form("#location-form",
        operation_location: %{name: "Repeater Site", geofence_radius_m: 250}
      )
      |> render_submit()

    assert html =~ "Repeater Site"
    reloaded = Operations.get_operation!(operation.id)
    assert Enum.count(reloaded.locations) == 2

    new_location = Enum.find(reloaded.locations, &(&1.name == "Repeater Site"))

    html =
      lv
      |> element("button[phx-value-id='#{new_location.id}']", "Remove")
      |> render_click()

    refute html =~ "Repeater Site"
    assert Enum.count(Operations.get_operation!(operation.id).locations) == 1
  end

  test "a single location added with a blank name defaults to Primary Site", %{conn: conn} do
    creator = McEmcomm.AccountsFixtures.user_fixture()

    {:ok, operation} =
      Operations.create_operation(%{
        "title" => "Single Site",
        "starts_at" => DateTime.utc_now(),
        "ends_at" => DateTime.add(DateTime.utc_now(), 3600, :second),
        "visibility" => "members",
        "created_by_id" => creator.id
      })

    {:ok, lv, _html} = live(conn, ~p"/admin/operations/#{operation.id}/edit")

    render_hook(lv, "point_selected", %{"lat" => 43.2, "lng" => -77.5})

    lv
    |> form("#location-form", operation_location: %{name: "", geofence_radius_m: 500})
    |> render_submit()

    assert [%{name: "Primary Site"}] = Operations.get_operation!(operation.id).locations
  end

  test "uploading an attachment with a description", %{conn: conn} do
    operation = McEmcommFixtures.operation_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/operations/#{operation.id}/edit")

    expect(StorageMock, :presign_upload, fn key, "text/plain" ->
      %{url: "https://tigris.example.com/upload", fields: %{"key" => key}}
    end)

    file =
      file_input(lv, "#attachment-form", :attachment, [
        %{name: "plan.txt", content: "the plan", type: "text/plain"}
      ])

    render_upload(file, "plan.txt")

    html =
      lv
      |> element("#attachment-form")
      |> render_submit(%{description: "Operations plan"})

    assert html =~ "Operations plan"
    assert html =~ "plan.txt"
  end

  test "copying an operation prefills the new form and carries over locations and attachments",
       %{conn: conn} do
    source =
      McEmcommFixtures.operation_fixture(
        %{"title" => "Field Day", "description" => "Annual", "visibility" => "public"},
        %{"name" => "HQ"}
      )

    {:ok, _} =
      Operations.create_operation_attachment(%{
        operation_id: source.id,
        key: "operation-attachments/original.txt",
        filename: "plan.txt",
        content_type: "text/plain",
        description: "Operations plan",
        uploaded_by_id: source.created_by_id
      })

    {:ok, index_lv, _html} = live(conn, ~p"/admin/operations")

    {:ok, lv, _html} =
      index_lv
      |> element("#copy-operation-#{source.id}")
      |> render_click()
      |> follow_redirect(conn, ~p"/admin/operations/#{source.id}/copy")

    assert has_element?(lv, "#copy-source-note", "Field Day")
    assert has_element?(lv, "#operation-form input[name='operation[title]'][value='Field Day']")
    assert has_element?(lv, "#operation-form input[name='operation[starts_at]']:not([value])")
    assert has_element?(lv, "#operation-form input[name='operation[ends_at]']:not([value])")
    assert has_element?(lv, "#copy-locations", "HQ")
    assert has_element?(lv, "#copy-attachments", "plan.txt")

    expect(StorageMock, :copy_object, fn "operation-attachments/original.txt", _new_key ->
      :ok
    end)

    {:ok, edit_lv, html} =
      lv
      |> form("#operation-form",
        operation: %{
          title: "Field Day 2027",
          starts_at: "2027-06-26T14:00",
          ends_at: "2027-06-27T14:00"
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Operation created"
    assert has_element?(edit_lv, "#operation-form")

    copy = Enum.find(Operations.list_operations(), &(&1.title == "Field Day 2027"))
    copy = Operations.get_operation!(copy.id)
    assert copy.visibility == :public
    assert copy.description == "Annual"
    assert [%{name: "HQ"}] = copy.locations

    assert [%{filename: "plan.txt", description: "Operations plan"} = attachment] =
             copy.attachments

    assert attachment.key != "operation-attachments/original.txt"
    assert Enum.count(Operations.get_operation!(source.id).attachments) == 1
  end

  test "the copy form requires a new window", %{conn: conn} do
    source = McEmcommFixtures.operation_fixture(%{"title" => "Field Day"})
    {:ok, lv, _html} = live(conn, ~p"/admin/operations/#{source.id}/copy")

    html =
      lv
      |> form("#operation-form", operation: %{title: "Field Day again"})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Enum.count(Operations.list_operations()) == 1
  end

  test "the edit page links to the copy form", %{conn: conn} do
    operation = McEmcommFixtures.operation_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/operations/#{operation.id}/edit")
    assert has_element?(lv, "#copy-operation[href='/admin/operations/#{operation.id}/copy']")
  end

  test "deleting an operation", %{conn: conn} do
    operation = McEmcommFixtures.operation_fixture(%{"title" => "To Delete"})
    {:ok, lv, _html} = live(conn, ~p"/admin/operations")

    lv |> element("button[phx-value-id='#{operation.id}']", "Delete") |> render_click()

    refute Enum.any?(Operations.list_operations(), &(&1.id == operation.id))
  end
end

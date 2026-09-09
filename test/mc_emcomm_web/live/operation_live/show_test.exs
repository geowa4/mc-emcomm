defmodule McEmcommWeb.OperationLive.ShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Operations
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  test "renders locations, attachments, and attendance", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    operation = McEmcommFixtures.operation_fixture()

    {:ok, lv, html} =
      conn |> log_in_user(member.user) |> live(~p"/app/operations/#{operation.id}")

    assert html =~ operation.title
    assert html =~ "Primary Site"
    assert html =~ "No attachments"
    assert html =~ "No recorded attendance yet"
    assert has_element?(lv, "button", "Mark my attendance")
    assert has_element?(lv, "#rsvps-empty")
    assert has_element?(lv, "#rsvp-form")
  end

  test "an approved member can RSVP and then change their answer", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2RSV"})
    operation = McEmcommFixtures.operation_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(member.user) |> live(~p"/app/operations/#{operation.id}")

    html =
      lv
      |> form("#rsvp-form", operation_rsvp: %{response: "yes", note: "arriving 1400"})
      |> render_submit()

    assert html =~ "RSVP saved"
    assert has_element?(lv, "#rsvp-count-yes", "1")
    assert has_element?(lv, "#rsvp-status", "Going")
    assert has_element?(lv, "#rsvps li", "W2RSV")
    assert has_element?(lv, "#rsvps li", "arriving 1400")
    refute has_element?(lv, "#rsvps-empty")
    assert Operations.get_rsvp(operation.id, member.id).response == :yes

    lv
    |> form("#rsvp-form", operation_rsvp: %{response: "no", note: ""})
    |> render_submit()

    assert has_element?(lv, "#rsvp-count-yes", "0")
    assert has_element?(lv, "#rsvp-count-no", "1")
    assert has_element?(lv, "#rsvp-status", "Not going")
    assert [rsvp] = Operations.list_rsvps(operation.id)
    assert rsvp.response == :no
    assert rsvp.note == nil
  end

  test "a blank response is shown as a form error", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    operation = McEmcommFixtures.operation_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(member.user) |> live(~p"/app/operations/#{operation.id}")

    html = lv |> form("#rsvp-form", operation_rsvp: %{response: ""}) |> render_submit()

    refute html =~ "RSVP saved"
    assert html =~ "can&#39;t be blank"
    assert Operations.list_rsvps(operation.id) == []
  end

  test "RSVPs close once the operation has ended", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    now = DateTime.utc_now()

    operation =
      McEmcommFixtures.operation_fixture(%{
        "starts_at" => DateTime.add(now, -7200, :second),
        "ends_at" => DateTime.add(now, -3600, :second)
      })

    {:ok, lv, _html} =
      conn |> log_in_user(member.user) |> live(~p"/app/operations/#{operation.id}")

    refute has_element?(lv, "#rsvp-form")
    assert has_element?(lv, "#rsvp-closed")
    assert has_element?(lv, "button", "Mark my attendance")
  end

  test "an approved member can mark their own attendance", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    operation = McEmcommFixtures.operation_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(member.user) |> live(~p"/app/operations/#{operation.id}")

    html = lv |> element("button", "Mark my attendance") |> render_click()

    assert html =~ "Attendance recorded"
    assert [attendance] = Operations.list_attendance(operation.id)
    assert attendance.member_id == member.id
    assert attendance.source == :manual
  end

  test "a download event carrying a junk id is declined, not crashed on", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    operation = McEmcommFixtures.operation_fixture()

    {:ok, lv, _html} =
      conn |> log_in_user(member.user) |> live(~p"/app/operations/#{operation.id}")

    assert render_click(lv, "download_attachment", %{"id" => "not-an-id"}) =~
             "no longer available"
  end

  test "downloading an attachment redirects to a presigned URL", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    operation = McEmcommFixtures.operation_fixture()

    {:ok, attachment} =
      Operations.create_operation_attachment(%{
        operation_id: operation.id,
        key: "operation-attachments/plan.pdf",
        filename: "plan.pdf",
        content_type: "application/pdf",
        description: "Operations plan",
        uploaded_by_id: member.user_id
      })

    expect(StorageMock, :presign_download_url, fn key ->
      assert key == attachment.key
      "https://tigris.example.com/plan.pdf?signed=1"
    end)

    {:ok, lv, html} =
      conn |> log_in_user(member.user) |> live(~p"/app/operations/#{operation.id}")

    assert html =~ "Operations plan"

    assert {:error, {:redirect, %{to: "https://tigris.example.com/plan.pdf?signed=1"}}} =
             lv |> element("button", "Download") |> render_click()
  end
end

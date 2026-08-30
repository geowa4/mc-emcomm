defmodule McEmcommWeb.AdminLive.MemberIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "approving a pending member", %{conn: conn} do
    member = McEmcommFixtures.pending_member_fixture(%{name: "Pat Pending"})
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv |> element("a", "Approve") |> render_click()

    assert Members.get_member!(member.id).status == :approved
  end

  test "rejecting a pending member requires a reason", %{conn: conn} do
    member = McEmcommFixtures.pending_member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv |> element("a", "Reject") |> render_click()
    assert has_element?(lv, "#reason-form")

    html =
      lv
      |> form("#reason-form", transition: %{reason: "Not a licensed operator"})
      |> render_submit()

    assert Members.get_member!(member.id).status == :rejected
    assert [audit] = Members.list_audit_for_member(member.id)
    assert audit.reason == "Not a licensed operator"
    refute html =~ "reason-form"
  end

  test "deactivating an approved member and reactivating", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv |> element("a", "Deactivate") |> render_click()

    lv
    |> form("#reason-form", transition: %{reason: "Moved away"})
    |> render_submit()

    assert Members.get_member!(member.id).status == :inactive

    lv |> element("a", "Reactivate") |> render_click()
    assert Members.get_member!(member.id).status == :approved
  end

  test "reopening a rejected member", %{conn: conn} do
    member = McEmcommFixtures.pending_member_fixture()
    actor = McEmcommFixtures.admin_scope_fixture().user
    {:ok, member} = Members.transition_status(member, :rejected, actor, "incomplete")

    {:ok, lv, _html} = live(conn, ~p"/admin/members")
    lv |> element("a", "Reopen") |> render_click()

    assert Members.get_member!(member.id).status == :pending
  end

  test "changing a member's role", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv
    |> element("form[phx-value-id='#{member.id}']")
    |> render_change(%{"role" => "treasurer"})

    assert Members.get_member!(member.id).role == :treasurer
  end

  test "viewing the audit trail", %{conn: conn} do
    McEmcommFixtures.pending_member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv |> element("a", "Approve") |> render_click()
    html = lv |> element("a", "Audit") |> render_click()

    assert html =~ "pending"
    assert html =~ "approved"
  end
end

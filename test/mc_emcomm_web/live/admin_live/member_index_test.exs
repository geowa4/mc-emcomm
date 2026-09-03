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

    lv |> element("button", "Approve") |> render_click()

    assert Members.get_member!(member.id).status == :approved
  end

  test "rejecting a pending member requires a reason", %{conn: conn} do
    member = McEmcommFixtures.pending_member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv |> element("button", "Reject") |> render_click()
    assert has_element?(lv, "#reason-modal")
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

    lv |> element("button", "Deactivate") |> render_click()

    lv
    |> form("#reason-form", transition: %{reason: "Moved away"})
    |> render_submit()

    assert Members.get_member!(member.id).status == :inactive

    lv |> element("button", "Reactivate") |> render_click()
    assert Members.get_member!(member.id).status == :approved
  end

  test "clicking the modal backdrop cancels the reason prompt", %{conn: conn} do
    McEmcommFixtures.member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv |> element("button", "Deactivate") |> render_click()
    assert has_element?(lv, "#reason-modal")

    lv |> element("#reason-modal .modal-backdrop") |> render_click()
    refute has_element?(lv, "#reason-modal")
  end

  test "reopening a rejected member", %{conn: conn} do
    member = McEmcommFixtures.pending_member_fixture()
    actor = McEmcommFixtures.admin_scope_fixture().user
    {:ok, member} = Members.transition_status(member, :rejected, actor, "incomplete")

    {:ok, lv, _html} = live(conn, ~p"/admin/members")
    lv |> element("button", "Reopen") |> render_click()

    assert Members.get_member!(member.id).status == :pending
  end

  test "assigning and removing a member's positions", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    treasurer = McEmcommFixtures.position_fixture(%{name: "Treasurer"})
    ec = McEmcommFixtures.position_fixture(%{name: "Emergency Coordinator"})

    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv
    |> element("#positions-form-#{member.id}")
    |> render_change(%{"position_ids" => ["", "#{treasurer.id}", "#{ec.id}"]})

    assert position_names(member) == ["Emergency Coordinator", "Treasurer"]

    lv
    |> element("#positions-form-#{member.id}")
    |> render_change(%{"position_ids" => [""]})

    assert position_names(member) == []
  end

  test "assigning a held position silently takes it over", %{conn: conn} do
    member_a = McEmcommFixtures.member_fixture(%{name: "Avery Holder"})
    member_b = McEmcommFixtures.member_fixture(%{name: "Blake Taker"})
    treasurer = McEmcommFixtures.position_fixture(%{name: "Treasurer"})

    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv
    |> element("#positions-form-#{member_a.id}")
    |> render_change(%{"position_ids" => ["", "#{treasurer.id}"]})

    lv
    |> element("#positions-form-#{member_b.id}")
    |> render_change(%{"position_ids" => ["", "#{treasurer.id}"]})

    assert position_names(member_b) == ["Treasurer"]
    assert position_names(member_a) == []

    refute has_element?(
             lv,
             "#positions-form-#{member_a.id} input[value='#{treasurer.id}'][checked]"
           )

    assert has_element?(
             lv,
             "#positions-form-#{member_b.id} input[value='#{treasurer.id}'][checked]"
           )
  end

  test "pending members are listed in their own section above the rest", %{conn: conn} do
    pending = McEmcommFixtures.pending_member_fixture(%{name: "Pat Pending"})
    approved = McEmcommFixtures.member_fixture(%{name: "Alex Approved"})

    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    assert has_element?(lv, "#pending-members tr#pending-members-#{pending.id}")
    refute has_element?(lv, "#members tr#members-#{pending.id}")
    assert has_element?(lv, "#members tr#members-#{approved.id}")
    refute has_element?(lv, "#pending-members-empty")

    lv |> element("#pending-members button", "Approve") |> render_click()

    assert has_element?(lv, "#pending-members-empty")
    assert has_element?(lv, "#members tr#members-#{pending.id}")
  end

  test "an inactive member's unheld position checkboxes are disabled", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    actor = McEmcommFixtures.admin_scope_fixture().user
    {:ok, member} = Members.transition_status(member, :inactive, actor, "moved")
    position = McEmcommFixtures.position_fixture(%{name: "Treasurer"})

    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    assert has_element?(
             lv,
             "#positions-form-#{member.id} input[value='#{position.id}'][disabled]"
           )
  end

  defp position_names(member) do
    member.id
    |> Members.get_member!()
    |> McEmcomm.Repo.preload(:positions)
    |> Map.fetch!(:positions)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  test "viewing the audit trail opens a modal", %{conn: conn} do
    McEmcommFixtures.pending_member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv |> element("button", "Approve") |> render_click()
    html = lv |> element("button", "Audit") |> render_click()

    assert has_element?(lv, "#audit-modal")
    assert html =~ "pending"
    assert html =~ "approved"
  end

  test "clicking the modal backdrop closes the audit trail", %{conn: conn} do
    McEmcommFixtures.member_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/members")

    lv |> element("button", "Audit") |> render_click()
    assert has_element?(lv, "#audit-modal")

    lv |> element("#audit-modal .modal-backdrop") |> render_click()
    refute has_element?(lv, "#audit-modal")
  end
end

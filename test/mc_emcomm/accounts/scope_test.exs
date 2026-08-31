defmodule McEmcomm.Accounts.ScopeTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.AccountsFixtures
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  describe "admin?/1" do
    test "true for a user with the admin flag" do
      assert McEmcommFixtures.admin_scope_fixture() |> Scope.admin?()
    end

    test "false for a plain approved member" do
      refute McEmcommFixtures.member_scope_fixture() |> Scope.admin?()
    end

    test "an approved member holding an admin-granting position is an admin" do
      member = McEmcommFixtures.member_fixture()
      position = McEmcommFixtures.position_fixture(%{grants_admin: true})
      {:ok, _} = Members.assign_position(member, position)

      assert member.user |> Scope.for_user() |> Scope.admin?()
    end

    test "holding a position that does not grant admin gives no admin access" do
      member = McEmcommFixtures.member_fixture()
      position = McEmcommFixtures.position_fixture()
      {:ok, _} = Members.assign_position(member, position)

      refute member.user |> Scope.for_user() |> Scope.admin?()
    end

    test "vacating the position removes the position-derived admin access" do
      member = McEmcommFixtures.member_fixture()
      position = McEmcommFixtures.position_fixture(%{grants_admin: true})
      {:ok, _} = Members.assign_position(member, position)
      :ok = Members.vacate_position(position)

      refute member.user |> Scope.for_user() |> Scope.admin?()
    end

    test "a holder made inactive loses the position-derived admin access" do
      member = McEmcommFixtures.member_fixture()
      position = McEmcommFixtures.position_fixture(%{grants_admin: true})
      {:ok, _} = Members.assign_position(member, position)

      actor = AccountsFixtures.user_fixture()
      {:ok, _} = Members.transition_status(member, :inactive, actor, "On hiatus")

      refute member.user |> Scope.for_user() |> Scope.admin?()
    end
  end
end

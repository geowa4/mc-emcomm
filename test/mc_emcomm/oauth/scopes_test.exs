defmodule McEmcomm.OAuth.ScopesTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.OAuth.Scopes

  describe "permitted_for/1 (scope ∩ live role, spec §28)" do
    test "an approved member may hold member and operations, never membership" do
      scope = McEmcommFixtures.member_scope_fixture()
      assert Scopes.permitted_for(scope) == ["emcomm:member", "emcomm:operations"]
      refute Scopes.permitted?(scope, "emcomm:membership")
    end

    test "an admin may hold every scope" do
      assert Scopes.permitted_for(McEmcommFixtures.admin_scope_fixture()) == Scopes.all()
    end

    test "a pending member, a user without a profile, and nobody get nothing" do
      pending = McEmcommFixtures.pending_member_fixture()
      assert Scopes.permitted_for(Scope.for_user(pending.user)) == []
      assert Scopes.permitted_for(McEmcomm.AccountsFixtures.user_scope_fixture()) == []
      assert Scopes.permitted_for(nil) == []
    end
  end

  describe "effective/2" do
    test "intersects the request with the role, in canonical order" do
      scope = McEmcommFixtures.member_scope_fixture()

      assert Scopes.effective(["emcomm:membership", "emcomm:operations", "emcomm:member"], scope) ==
               ["emcomm:member", "emcomm:operations"]

      assert Scopes.effective(["emcomm:membership"], scope) == []
    end

    test "an empty request means everything the role permits" do
      assert Scopes.effective([], McEmcommFixtures.admin_scope_fixture()) == Scopes.all()
    end
  end

  describe "parse/1" do
    test "accepts a space-delimited list and rejects unknown scopes" do
      assert Scopes.parse("emcomm:operations emcomm:member") ==
               {:ok, ["emcomm:member", "emcomm:operations"]}

      assert Scopes.parse(nil) == {:ok, []}
      assert Scopes.parse("") == {:ok, []}
      assert Scopes.parse("emcomm:member openid") == {:error, :invalid_scope}
    end
  end
end

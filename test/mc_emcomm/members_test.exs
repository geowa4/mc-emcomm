defmodule McEmcomm.MembersTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.AccountsFixtures
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  describe "transition_status/4 — legal transitions" do
    test "pending -> approved (no reason required), writes an audit row" do
      member = McEmcommFixtures.pending_member_fixture()
      actor = AccountsFixtures.user_fixture()

      assert {:ok, %{status: :approved}} = Members.transition_status(member, :approved, actor)

      assert [%{from_status: "pending", to_status: "approved", reason: nil}] =
               Members.list_audit_for_member(member.id)
    end

    test "pending -> rejected requires a reason" do
      member = McEmcommFixtures.pending_member_fixture()
      actor = AccountsFixtures.user_fixture()

      assert {:error, changeset} = Members.transition_status(member, :rejected, actor)
      assert %{reason: ["can't be blank"]} = errors_on(changeset)

      assert {:ok, %{status: :rejected}} =
               Members.transition_status(member, :rejected, actor, "Not a licensed operator")

      assert [%{to_status: "rejected", reason: "Not a licensed operator"}] =
               Members.list_audit_for_member(member.id)
    end

    test "approved -> inactive requires a reason" do
      member = McEmcommFixtures.member_fixture()
      actor = AccountsFixtures.user_fixture()

      assert {:error, _} = Members.transition_status(member, :inactive, actor)

      assert {:ok, %{status: :inactive}} =
               Members.transition_status(member, :inactive, actor, "Moved away")
    end

    test "inactive -> approved (reactivation)" do
      member = McEmcommFixtures.member_fixture()
      actor = AccountsFixtures.user_fixture()
      {:ok, member} = Members.transition_status(member, :inactive, actor, "On hiatus")

      assert {:ok, %{status: :approved}} = Members.transition_status(member, :approved, actor)
    end

    test "rejected -> pending (reopen)" do
      member = McEmcommFixtures.pending_member_fixture()
      actor = AccountsFixtures.user_fixture()

      {:ok, member} =
        Members.transition_status(member, :rejected, actor, "Incomplete application")

      assert {:ok, %{status: :pending}} = Members.transition_status(member, :pending, actor)
    end
  end

  describe "transition_status/4 — illegal transitions" do
    illegal = [
      {:pending, :inactive},
      {:approved, :pending},
      {:approved, :rejected},
      {:rejected, :approved},
      {:rejected, :inactive},
      {:inactive, :pending},
      {:inactive, :rejected}
    ]

    for {from, to} <- illegal do
      test "#{from} -> #{to} is rejected and writes no new audit row" do
        member = build_member_in_status(unquote(from))
        actor = AccountsFixtures.user_fixture()
        audit_before = Members.list_audit_for_member(member.id)

        assert {:error, :illegal_transition} =
                 Members.transition_status(member, unquote(to), actor, "some reason")

        assert Members.list_audit_for_member(member.id) == audit_before
      end
    end

    defp build_member_in_status(:pending), do: McEmcommFixtures.pending_member_fixture()

    defp build_member_in_status(:approved), do: McEmcommFixtures.member_fixture()

    defp build_member_in_status(:rejected) do
      member = McEmcommFixtures.pending_member_fixture()
      actor = AccountsFixtures.user_fixture()
      {:ok, member} = Members.transition_status(member, :rejected, actor, "reason")
      member
    end

    defp build_member_in_status(:inactive) do
      member = McEmcommFixtures.member_fixture()
      actor = AccountsFixtures.user_fixture()
      {:ok, member} = Members.transition_status(member, :inactive, actor, "reason")
      member
    end
  end
end

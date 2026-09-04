defmodule McEmcomm.MembersTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.AccountsFixtures
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members
  alias McEmcomm.Members.MemberPosition

  describe "update_profile/2 — emergency contact" do
    test "is optional and blank fields are stored as nil" do
      member = McEmcommFixtures.member_fixture()

      assert {:ok, member} =
               Members.update_profile(member, %{
                 emergency_contact_name: "",
                 emergency_contact_phone: "  ",
                 emergency_contact_relation: ""
               })

      assert member.emergency_contact_name == nil
      assert member.emergency_contact_phone == nil
      assert member.emergency_contact_relation == nil
    end

    test "requires name and phone once any field is given" do
      member = McEmcommFixtures.member_fixture()

      assert {:error, changeset} =
               Members.update_profile(member, %{emergency_contact_relation: "Spouse"})

      assert %{emergency_contact_name: ["can't be blank"], emergency_contact_phone: _} =
               errors_on(changeset)

      assert {:ok, member} =
               Members.update_profile(member, %{
                 emergency_contact_name: "Pat Example",
                 emergency_contact_phone: "+1 585 555 0100"
               })

      assert member.emergency_contact_relation == nil
    end

    test "rejects a phone number that is not a phone number" do
      member = McEmcommFixtures.member_fixture()

      assert {:error, changeset} =
               Members.update_profile(member, %{
                 emergency_contact_name: "Pat Example",
                 emergency_contact_phone: "call my office"
               })

      assert %{emergency_contact_phone: ["must be a phone number"]} = errors_on(changeset)
    end

    test "can be cleared again" do
      member = McEmcommFixtures.member_fixture()

      {:ok, member} =
        Members.update_profile(member, %{
          emergency_contact_name: "Pat Example",
          emergency_contact_phone: "585-555-0100"
        })

      assert {:ok, member} =
               Members.update_profile(member, %{
                 emergency_contact_name: "",
                 emergency_contact_phone: ""
               })

      assert member.emergency_contact_name == nil
      assert member.emergency_contact_phone == nil
    end
  end

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

    test "approved -> inactive vacates every position the member holds" do
      member = McEmcommFixtures.member_fixture()
      president = McEmcommFixtures.position_fixture(%{name: "President"})
      secretary = McEmcommFixtures.position_fixture(%{name: "Secretary"})
      {:ok, _} = Members.update_member_positions(member, [president.id, secretary.id])
      actor = AccountsFixtures.user_fixture()

      assert {:ok, _} = Members.transition_status(member, :inactive, actor, "Moved away")

      assert Enum.all?(Members.list_positions(), &(&1.members == []))
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

  describe "positions" do
    test "list_positions/0 returns every position in sort order, vacancies included" do
      McEmcommFixtures.position_fixture(%{name: "Secretary", sort_order: 3})
      McEmcommFixtures.position_fixture(%{name: "President", sort_order: 1})
      McEmcommFixtures.position_fixture(%{name: "Vice-President", sort_order: 2})

      positions = Members.list_positions()

      assert Enum.map(positions, & &1.name) == ["President", "Vice-President", "Secretary"]
      assert Enum.all?(positions, &(&1.members == []))
    end

    test "holds_admin_position?/1 follows admin-granting positions as they change hands" do
      member = McEmcommFixtures.member_fixture()
      plain = McEmcommFixtures.position_fixture(%{name: "Secretary"})
      admin_pos = McEmcommFixtures.position_fixture(%{name: "President", grants_admin: true})

      refute Members.holds_admin_position?(member.id)

      {:ok, _} = Members.update_member_positions(member, [plain.id])
      refute Members.holds_admin_position?(member.id)

      {:ok, _} = Members.assign_position(member, admin_pos)
      assert Members.holds_admin_position?(member.id)

      :ok = Members.vacate_position(admin_pos)
      refute Members.holds_admin_position?(member.id)
    end

    test "update_member_positions/2 lets one member hold several positions" do
      member = McEmcommFixtures.member_fixture()
      vp = McEmcommFixtures.position_fixture(%{name: "Vice-President", sort_order: 1})
      ec = McEmcommFixtures.position_fixture(%{name: "Emergency Coordinator", sort_order: 2})

      assert {:ok, _} = Members.update_member_positions(member, [vp.id, ec.id])

      held =
        Members.list_positions()
        |> Enum.filter(fn p -> Enum.any?(p.members, &(&1.id == member.id)) end)
        |> Enum.map(& &1.name)

      assert held == ["Vice-President", "Emergency Coordinator"]

      assert {:ok, _} = Members.update_member_positions(member, [ec.id])

      assert [%{name: "Emergency Coordinator"}] =
               Members.list_positions()
               |> Enum.filter(fn p -> Enum.any?(p.members, &(&1.id == member.id)) end)
    end

    test "update_member_positions/2 takes a position over from its current holder" do
      member_a = McEmcommFixtures.member_fixture()
      member_b = McEmcommFixtures.member_fixture()
      secretary = McEmcommFixtures.position_fixture(%{name: "Secretary"})
      treasurer = McEmcommFixtures.position_fixture(%{name: "Treasurer"})

      {:ok, _} = Members.update_member_positions(member_a, [secretary.id, treasurer.id])
      {:ok, _} = Members.update_member_positions(member_b, [treasurer.id])

      treasurer_after = Enum.find(Members.list_positions(), &(&1.name == "Treasurer"))
      assert Enum.map(treasurer_after.members, & &1.id) == [member_b.id]

      secretary_after = Enum.find(Members.list_positions(), &(&1.name == "Secretary"))
      assert Enum.map(secretary_after.members, & &1.id) == [member_a.id]
    end

    test "the database rejects two holders of one position" do
      member_a = McEmcommFixtures.member_fixture()
      member_b = McEmcommFixtures.member_fixture()
      president = McEmcommFixtures.position_fixture(%{name: "President"})
      now = DateTime.utc_now(:second)

      rows =
        for m <- [member_a, member_b] do
          %{member_id: m.id, position_id: president.id, inserted_at: now, updated_at: now}
        end

      assert_raise Postgrex.Error, ~r/member_positions_position_id_index/, fn ->
        McEmcomm.Repo.insert_all("member_positions", rows)
      end
    end

    test "create/update/delete a position" do
      {:ok, position} = Members.create_position(%{name: "Webmaster", sort_order: 1})

      {:ok, position} = Members.update_position(position, %{name: "Web Coordinator"})
      assert Members.get_position!(position.id).name == "Web Coordinator"

      assert {:ok, _} = Members.delete_position(position)
      assert Members.list_positions() == []
    end

    test "create_position/1 rejects a non-positive sort order" do
      assert {:error, changeset} =
               Members.create_position(%{name: "Net Manager", sort_order: -25})

      assert %{sort_order: ["must be greater than 0"]} = errors_on(changeset)

      assert {:error, changeset} = Members.create_position(%{name: "Net Manager", sort_order: 0})
      assert %{sort_order: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "create_position/1 rejects a duplicate name or sort order" do
      McEmcommFixtures.position_fixture(%{name: "President", sort_order: 1})

      assert {:error, changeset} = Members.create_position(%{name: "President", sort_order: 2})
      assert %{name: ["has already been taken"]} = errors_on(changeset)

      assert {:error, changeset} = Members.create_position(%{name: "Treasurer", sort_order: 1})
      assert %{sort_order: ["has already been taken"]} = errors_on(changeset)
    end

    test "reorder_positions/1 renumbers to match the given order" do
      a = McEmcommFixtures.position_fixture(%{name: "President", sort_order: 1})
      b = McEmcommFixtures.position_fixture(%{name: "Secretary", sort_order: 2})
      c = McEmcommFixtures.position_fixture(%{name: "Treasurer", sort_order: 3})

      assert :ok = Members.reorder_positions([c.id, a.id, b.id])

      assert Members.list_positions() |> Enum.map(&{&1.name, &1.sort_order}) == [
               {"Treasurer", 1},
               {"President", 2},
               {"Secretary", 3}
             ]
    end

    test "reorder_positions/1 refuses a stale id list" do
      a = McEmcommFixtures.position_fixture(%{name: "President", sort_order: 1})
      McEmcommFixtures.position_fixture(%{name: "Secretary", sort_order: 2})

      assert {:error, :stale} = Members.reorder_positions([a.id])

      assert Members.list_positions() |> Enum.map(& &1.sort_order) == [1, 2]
    end

    test "delete_position/1 refuses while a member holds the position" do
      member = McEmcommFixtures.member_fixture()
      position = McEmcommFixtures.position_fixture(%{name: "President"})
      {:ok, _} = Members.update_member_positions(member, [position.id])

      assert {:error, :position_held} = Members.delete_position(position)

      {:ok, _} = Members.update_member_positions(member, [])
      assert {:ok, _} = Members.delete_position(position)
    end

    test "list_positions/0 only includes approved holders" do
      # A non-approved holder can't arise through the public API (leaving
      # approved status vacates positions), so seed one directly to prove
      # the public listing filters it out as defense in depth.
      member = McEmcommFixtures.pending_member_fixture()
      president = McEmcommFixtures.position_fixture(%{name: "President"})
      Repo.insert!(%MemberPosition{member_id: member.id, position_id: president.id})

      president_after = Enum.find(Members.list_positions(), &(&1.name == "President"))
      assert president_after.members == []

      president_all = Enum.find(Members.list_positions(holders: :all), &(&1.name == "President"))
      assert [%{id: id}] = president_all.members
      assert id == member.id
    end

    test "update_member_positions/2 refuses to give a non-approved member a position" do
      pending = McEmcommFixtures.pending_member_fixture()
      president = McEmcommFixtures.position_fixture(%{name: "President"})

      assert {:error, :not_approved} = Members.update_member_positions(pending, [president.id])

      president_after =
        Enum.find(Members.list_positions(holders: :all), &(&1.name == "President"))

      assert president_after.members == []
    end

    test "update_member_positions/2 refuses to give a deactivated member a position back" do
      member = McEmcommFixtures.member_fixture()
      actor = AccountsFixtures.user_fixture()
      secretary = McEmcommFixtures.position_fixture(%{name: "Secretary"})

      {:ok, _} = Members.update_member_positions(member, [secretary.id])
      {:ok, member} = Members.transition_status(member, :inactive, actor, "Moved away")

      assert {:error, :not_approved} = Members.update_member_positions(member, [secretary.id])
    end

    test "assign_position/2 refuses a non-approved member" do
      pending = McEmcommFixtures.pending_member_fixture()
      president = McEmcommFixtures.position_fixture(%{name: "President"})

      assert {:error, :not_approved} = Members.assign_position(pending, president)
    end

    test "search_members_by_call_sign/1 matches partial call signs case-insensitively" do
      a = McEmcommFixtures.member_fixture(%{name: "Avery", call_sign: "W2AAA"})
      McEmcommFixtures.member_fixture(%{name: "Blake", call_sign: "K2BBB"})
      McEmcommFixtures.pending_member_fixture(%{name: "Pat", call_sign: "W2AAP"})

      assert [%{id: id}] = Members.search_members_by_call_sign("w2a")
      assert id == a.id

      assert length(Members.search_members_by_call_sign("2")) == 2
      assert Members.search_members_by_call_sign("XX") == []
      assert Members.search_members_by_call_sign("  ") == []
    end

    test "assign_position/2 keeps the member's other positions and takes over the new one" do
      member_a = McEmcommFixtures.member_fixture()
      member_b = McEmcommFixtures.member_fixture()
      secretary = McEmcommFixtures.position_fixture(%{name: "Secretary"})
      treasurer = McEmcommFixtures.position_fixture(%{name: "Treasurer"})

      {:ok, _} = Members.update_member_positions(member_a, [secretary.id])
      {:ok, _} = Members.update_member_positions(member_b, [treasurer.id])

      {:ok, _} = Members.assign_position(member_a, treasurer)

      held_by_a =
        Members.list_positions()
        |> Enum.filter(fn p -> Enum.any?(p.members, &(&1.id == member_a.id)) end)
        |> Enum.map(& &1.name)

      assert held_by_a == ["Secretary", "Treasurer"]

      treasurer_after = Enum.find(Members.list_positions(), &(&1.name == "Treasurer"))
      assert Enum.map(treasurer_after.members, & &1.id) == [member_a.id]
    end

    test "vacate_position/1 removes the holder" do
      member = McEmcommFixtures.member_fixture()
      president = McEmcommFixtures.position_fixture(%{name: "President"})
      {:ok, _} = Members.update_member_positions(member, [president.id])

      assert :ok = Members.vacate_position(president)

      president_after = Enum.find(Members.list_positions(), &(&1.name == "President"))
      assert president_after.members == []
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

defmodule McEmcomm.MembersNotificationTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.AccountsFixtures
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  # Fixtures deliver confirmation emails to this process too, so a bare
  # refute_email_sent/0 would trip on those; only the new-member notice counts.
  defp refute_new_member_notice do
    refute_receive {:email, %Swoosh.Email{subject: "New member awaiting approval" <> _}}
  end

  describe "list_new_member_notification_recipients/0" do
    test "returns approved holders of flagged positions, each once" do
      holder = McEmcommFixtures.member_fixture()
      other_holder = McEmcommFixtures.member_fixture()
      _unflagged_holder = McEmcommFixtures.member_fixture()

      flagged = McEmcommFixtures.position_fixture(%{notify_on_new_member: true})
      also_flagged = McEmcommFixtures.position_fixture(%{notify_on_new_member: true})
      _vacant = McEmcommFixtures.position_fixture(%{notify_on_new_member: true})
      unflagged = McEmcommFixtures.position_fixture()

      {:ok, _} = Members.update_member_positions(holder, [flagged.id, also_flagged.id])
      {:ok, _} = Members.assign_position(other_holder, unflagged)

      recipient_ids = Members.list_new_member_notification_recipients() |> Enum.map(& &1.id)

      assert recipient_ids == [holder.user.id]
    end

    test "excludes holders who are no longer approved" do
      holder = McEmcommFixtures.member_fixture()
      admin = AccountsFixtures.user_fixture()
      flagged = McEmcommFixtures.position_fixture(%{notify_on_new_member: true})
      {:ok, _} = Members.assign_position(holder, flagged)

      # Deactivating vacates positions; the join must not resurrect the holder.
      {:ok, _} = Members.transition_status(holder, :inactive, admin, "moved away")

      assert Members.list_new_member_notification_recipients() == []
    end
  end

  describe "notify_new_member_confirmed/1" do
    test "emails every recipient about the new member" do
      holder = McEmcommFixtures.member_fixture()
      flagged = McEmcommFixtures.position_fixture(%{notify_on_new_member: true})
      {:ok, _} = Members.assign_position(holder, flagged)

      new_member = McEmcommFixtures.pending_member_fixture(%{name: "Newcomer"})

      assert :ok = Members.notify_new_member_confirmed(new_member.user)

      holder_email = holder.user.email

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "New member awaiting approval: Newcomer",
                        to: [{_, ^holder_email}]
                      }}
    end

    test "is a no-op when no position is flagged" do
      holder = McEmcommFixtures.member_fixture()
      position = McEmcommFixtures.position_fixture()
      {:ok, _} = Members.assign_position(holder, position)
      new_member = McEmcommFixtures.pending_member_fixture()

      assert :ok = Members.notify_new_member_confirmed(new_member.user)
      refute_new_member_notice()
    end

    test "is a no-op for a user without a member profile" do
      holder = McEmcommFixtures.member_fixture()
      flagged = McEmcommFixtures.position_fixture(%{notify_on_new_member: true})
      {:ok, _} = Members.assign_position(holder, flagged)

      assert :ok = Members.notify_new_member_confirmed(AccountsFixtures.user_fixture())
      refute_new_member_notice()
    end
  end
end

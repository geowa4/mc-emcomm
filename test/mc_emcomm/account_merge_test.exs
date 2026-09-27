defmodule McEmcomm.AccountMergeTest do
  use McEmcomm.DataCase, async: true

  import Mox
  import McEmcomm.AccountsFixtures
  import McEmcomm.McEmcommFixtures
  import McEmcomm.OAuthFixtures

  alias McEmcomm.AccountMerge
  alias McEmcomm.Accounts
  alias McEmcomm.Accounts.{RecoveryCode, User, UserToken}
  alias McEmcomm.Capabilities
  alias McEmcomm.Certifications
  alias McEmcomm.Courses
  alias McEmcomm.Members
  alias McEmcomm.Members.{Member, MembershipAudit}
  alias McEmcomm.Net
  alias McEmcomm.OAuth
  alias McEmcomm.Operations
  alias McEmcomm.Operations.{OperationAttendance, OperationRsvp}
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  defp merge_accounts(survivor, other, selected \\ []) do
    AccountMerge.merge(survivor, email_claim_token(survivor, other.email), selected)
  end

  defp item(plan, key), do: Enum.find(plan.items, &(&1.key == key))

  defp update_member!(member, changes) do
    member |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  describe "plan/2" do
    test "offers profile details that differ, suggesting the ones that fill a gap" do
      mine = member_fixture(%{name: "Pat Example"})

      theirs =
        member_fixture(%{name: "Patricia Example", call_sign: "W2PAT"})
        |> update_member!(
          license_class: :general,
          qth_address: "1 Main St",
          emergency_contact_name: "Sam",
          emergency_contact_phone: "585-555-0100"
        )

      plan = AccountMerge.plan(mine.user, theirs.user)

      assert plan.blocked == nil
      refute plan.adopts_profile?

      assert %{mine: "Pat Example", theirs: "Patricia Example", default: false} =
               item(plan, "name")

      assert %{mine: nil, theirs: "W2PAT", default: true} = item(plan, "call_sign")
      assert %{theirs: "General", default: true} = item(plan, "license_class")
      assert %{theirs: "1 Main St", default: true} = item(plan, "qth")
      assert %{theirs: "Sam, 585-555-0100", default: true} = item(plan, "emergency_contact")
    end

    test "leaves out details that match or that the other profile lacks" do
      mine = member_fixture(%{name: "Same Name", call_sign: "W2ONE"})
      theirs = member_fixture(%{name: "Same Name"})

      assert AccountMerge.plan(mine.user, theirs.user).items == []
    end

    test "offers training records, keeping the survivor's own by default" do
      mine = member_fixture()
      theirs = member_fixture()
      shared = course_fixture(%{name: "Shared Course"})
      extra = course_fixture(%{name: "Extra Course"})
      certification = certification_fixture()
      capability = capability_fixture()
      both = capability_fixture()

      {:ok, _} = Courses.add_member_course(%{member_id: mine.id, course_id: shared.id})

      {:ok, _} =
        Courses.add_member_course(%{
          member_id: theirs.id,
          course_id: shared.id,
          completed_on: ~D[2026-01-02],
          evidence_filename: "proof.pdf"
        })

      {:ok, _} = Courses.add_member_course(%{member_id: theirs.id, course_id: extra.id})

      {:ok, _} =
        Certifications.add_member_certification(%{
          member_id: theirs.id,
          certification_id: certification.id,
          issued_on: ~D[2026-02-03]
        })

      for member <- [mine, theirs] do
        {:ok, _} =
          Capabilities.add_member_capability(%{member_id: member.id, capability_id: both.id})
      end

      {:ok, _} =
        Capabilities.add_member_capability(%{member_id: theirs.id, capability_id: capability.id})

      plan = AccountMerge.plan(mine.user, theirs.user)

      assert %{
               group: :courses,
               mine: "On record",
               theirs: "Completed 2026-01-02, evidence proof.pdf",
               default: false
             } = item(plan, "course:#{shared.id}")

      assert %{mine: nil, theirs: "On record", default: true} = item(plan, "course:#{extra.id}")

      assert %{group: :certifications, theirs: "Issued 2026-02-03", default: true} =
               item(plan, "certification:#{certification.id}")

      assert %{group: :capabilities, default: true} = item(plan, "capability:#{capability.id}")
      refute item(plan, "capability:#{both.id}")
    end

    test "reports the standing the survivor would inherit" do
      mine = pending_member_fixture()
      theirs = member_fixture()
      position = position_fixture()
      {:ok, _} = Members.assign_position(theirs, position)
      {:ok, other} = Accounts.promote_to_admin(theirs.user)

      plan = AccountMerge.plan(mine.user, other)

      assert plan.gains.approved?
      assert plan.gains.admin?
      assert Enum.map(plan.gains.positions, & &1.id) == [position.id]
    end

    test "inherits nothing the survivor already has or that is not better" do
      mine = member_fixture()
      theirs = pending_member_fixture()

      assert %{approved?: false, positions: [], admin?: false} =
               AccountMerge.plan(mine.user, theirs.user).gains
    end

    test "adopts the other profile when the survivor has none" do
      theirs = member_fixture()
      plan = AccountMerge.plan(user_fixture(), theirs.user)

      assert plan.adopts_profile?
      assert plan.items == []
      refute plan.gains.approved?
    end

    test "is blocked by two-factor authentication on the other account" do
      %{user: other} = user_with_totp_fixture()
      assert AccountMerge.plan(user_fixture(), other).blocked == :two_factor
    end
  end

  describe "merge/3 — accounts" do
    test "moves every address and deactivates the other account" do
      survivor = user_fixture()
      other = set_password(user_fixture())
      extra = user_email_fixture(other)
      _session = Accounts.generate_user_session_token(other)
      tokens_fixture(other)

      assert {:ok, %{user: %User{} = merged, expired_tokens: expired}} =
               merge_accounts(survivor, other)

      assert merged.id == survivor.id
      assert Enum.any?(expired, &(&1.context == "session"))

      assert survivor |> Accounts.list_user_emails() |> Enum.map(& &1.email) |> Enum.sort() ==
               Enum.sort([other.email, extra.email])

      assert Accounts.get_user_by_email(other.email).id == survivor.id
      assert Accounts.get_user_by_email(extra.email).id == survivor.id

      deactivated = Accounts.get_user!(other.id)
      assert deactivated.email == "merged-user-#{other.id}@deactivated.invalid"
      assert deactivated.deactivated_at
      assert deactivated.merged_into_id == survivor.id
      assert deactivated.hashed_password == nil
      refute deactivated.is_admin

      refute Repo.exists?(from t in UserToken, where: t.user_id == ^other.id)
      refute Repo.exists?(from t in OAuth.Token, where: t.user_id == ^other.id)
      refute Repo.exists?(from t in UserToken, where: t.context == "add_email")

      refute Accounts.get_user_by_email(deactivated.email)
      refute Accounts.get_user_by_email_and_password(other.email, "wrong password!")
    end

    test "a deactivated account cannot use a session or login link it still holds" do
      survivor = user_fixture()
      other = user_fixture()
      {:ok, _} = merge_accounts(survivor, other)

      deactivated = Accounts.get_user!(other.id)
      session = Accounts.generate_user_session_token(deactivated)
      {login, _hashed} = generate_user_magic_link_token(deactivated)

      refute Accounts.get_user_by_session_token(session)
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(login)
    end

    test "re-points what the other user authored" do
      survivor = user_fixture()
      {:ok, other} = Accounts.promote_to_admin(user_fixture())
      about = pending_member_fixture()
      {:ok, _} = Members.transition_status(about, :approved, other)

      {:ok, operation} =
        Operations.create_operation(%{
          "title" => "Authored",
          "starts_at" => DateTime.utc_now(),
          "ends_at" => DateTime.add(DateTime.utc_now(), 3600, :second),
          "visibility" => "members",
          "created_by_id" => other.id
        })

      {:ok, attachment} =
        Operations.create_operation_attachment(%{
          operation_id: operation.id,
          key: "operations/plan.pdf",
          filename: "plan.pdf",
          content_type: "application/pdf",
          description: "Plan",
          uploaded_by_id: other.id
        })

      assert {:ok, %{user: merged}} = merge_accounts(survivor, other)

      assert merged.is_admin
      assert [%MembershipAudit{actor_user_id: actor}] = Members.list_audit_for_member(about.id)
      assert actor == survivor.id
      assert Operations.get_operation!(operation.id).created_by_id == survivor.id
      assert Repo.reload!(attachment).uploaded_by_id == survivor.id
    end

    test "refuses an account with two-factor authentication and changes nothing" do
      survivor = user_fixture()
      %{user: other} = user_with_totp_fixture()

      assert {:error, :two_factor} = merge_accounts(survivor, other)

      assert Accounts.get_user!(other.id).email == other.email
      assert Accounts.list_user_emails(survivor) == []
      assert Repo.exists?(from r in RecoveryCode, where: r.user_id == ^other.id)
    end

    test "refuses a bad token, somebody else's token, and a second use" do
      survivor = user_fixture()
      other = user_fixture()
      token = email_claim_token(survivor, other.email)

      assert {:error, :invalid} = AccountMerge.merge(survivor, "nonsense", [])
      assert {:error, :invalid} = AccountMerge.merge(user_fixture(), token, [])
      # The holder of the address cannot turn the link around either.
      assert {:error, :invalid} = AccountMerge.merge(other, token, [])

      assert {:ok, _} = AccountMerge.merge(survivor, token, [])
      assert {:error, :invalid} = AccountMerge.merge(survivor, token, [])
    end

    test "refuses a link for an address nobody else holds any more" do
      survivor = user_fixture()
      other = user_fixture()
      extra = user_email_fixture(other)
      token = email_claim_token(survivor, extra.email)
      {:ok, _} = Accounts.remove_user_email(other, extra.id)

      assert {:error, :invalid} = AccountMerge.merge(survivor, token, [])
    end
  end

  describe "merge/3 — profiles" do
    test "copies only the chosen details and ignores unknown keys" do
      mine = member_fixture(%{name: "Pat Example"})

      theirs =
        member_fixture(%{name: "Patricia Example", call_sign: "W2PAT"})
        |> update_member!(license_class: :general, qth_address: "1 Main St")

      assert {:ok, _} =
               merge_accounts(mine.user, theirs.user, ["call_sign", "qth", "is_admin", "course:0"])

      merged = Members.get_member!(mine.id)
      assert merged.name == "Pat Example"
      assert merged.call_sign == "W2PAT"
      assert merged.qth_address == "1 Main St"
      assert merged.license_class == nil
      assert merged.status == :approved

      retired = Members.get_member!(theirs.id)
      assert retired.status == :inactive
      assert retired.call_sign == nil
      assert retired.name == "Patricia Example"

      assert [%MembershipAudit{} = audit | _] = Members.list_audit_for_member(theirs.id)
      assert audit.from_status == "approved"
      assert audit.to_status == "inactive"
      assert audit.reason == "Merged into #{mine.user.email}"
      assert audit.actor_user_id == mine.user.id
    end

    test "moves chosen training, replacing the survivor's record and purging its files" do
      mine = member_fixture()
      theirs = member_fixture()
      course = course_fixture()
      skipped = course_fixture()
      certification = certification_fixture()
      capability = capability_fixture()

      {:ok, _} =
        Courses.add_member_course(%{
          member_id: mine.id,
          course_id: course.id,
          evidence_key: "member-uploads/old.pdf"
        })

      {:ok, moved} =
        Courses.add_member_course(%{
          member_id: theirs.id,
          course_id: course.id,
          evidence_key: "member-uploads/new.pdf"
        })

      {:ok, _} = Courses.add_member_course(%{member_id: theirs.id, course_id: skipped.id})

      {:ok, _} =
        Certifications.add_member_certification(%{
          member_id: theirs.id,
          certification_id: certification.id
        })

      {:ok, _} =
        Capabilities.add_member_capability(%{member_id: theirs.id, capability_id: capability.id})

      expect(StorageMock, :delete_object, fn "member-uploads/old.pdf" -> :ok end)

      assert {:ok, _} =
               merge_accounts(mine.user, theirs.user, [
                 "course:#{course.id}",
                 "certification:#{certification.id}",
                 "capability:#{capability.id}"
               ])

      assert [%{id: id, evidence_key: "member-uploads/new.pdf"}] =
               Courses.list_member_courses(mine.id)

      assert id == moved.id
      assert [%{course_id: left}] = Courses.list_member_courses(theirs.id)
      assert left == skipped.id
      assert [_] = Certifications.list_member_certifications(mine.id)
      assert [_] = Capabilities.list_member_capabilities(mine.id)
    end

    test "moves activity, keeping the survivor's own reply where both have one" do
      mine = member_fixture()
      theirs = member_fixture(%{call_sign: "W2ACT"})
      both = operation_fixture()
      only = operation_fixture()

      {:ok, _} = Operations.rsvp(both, mine.id, %{"response" => "yes"})
      {:ok, _} = Operations.rsvp(both, theirs.id, %{"response" => "no"})
      {:ok, _} = Operations.rsvp(only, theirs.id, %{"response" => "maybe"})
      {:ok, _} = Operations.record_attendance(only.id, theirs.id, :manual)

      session = net_session_fixture(theirs)
      {:ok, session} = Net.assign_net_control(session, theirs)
      {:ok, checkin} = Net.check_in(session, %{"call_sign" => "W2ACT"})
      assert checkin.member_id == theirs.id

      assert {:ok, _} = merge_accounts(mine.user, theirs.user)

      assert %OperationRsvp{response: :yes} = Operations.get_rsvp(both.id, mine.id)
      assert %OperationRsvp{response: :maybe} = Operations.get_rsvp(only.id, mine.id)
      assert %OperationRsvp{response: :no} = Operations.get_rsvp(both.id, theirs.id)
      assert [%OperationAttendance{member_id: attended}] = Operations.list_attendance(only.id)
      assert attended == mine.id

      session = Net.get_session!(session.id)
      assert session.started_by_member_id == mine.id
      assert session.net_control_member_id == mine.id
      assert Repo.reload!(checkin).member_id == mine.id
    end

    test "inherits an approved membership and its positions, with an audit row" do
      mine = pending_member_fixture()
      theirs = member_fixture()
      position = position_fixture(%{grants_admin: true})
      {:ok, _} = Members.assign_position(theirs, position)

      assert {:ok, %{user: merged}} = merge_accounts(mine.user, theirs.user)

      assert Members.get_member!(mine.id).status == :approved
      assert Members.holds_admin_position?(mine.id)
      refute Members.holds_admin_position?(theirs.id)
      assert Accounts.Scope.admin?(Accounts.Scope.for_user(merged))

      assert [%MembershipAudit{} = audit] = Members.list_audit_for_member(mine.id)
      assert audit.from_status == "pending"
      assert audit.to_status == "approved"
      assert audit.reason == "Merged with #{theirs.user.email}"
    end

    test "vacates positions when the surviving profile is not approved" do
      mine = pending_member_fixture()
      theirs = member_fixture()
      position = position_fixture()
      {:ok, _} = Members.assign_position(theirs, position)

      admin = admin_scope_fixture().user
      {:ok, theirs} = Members.transition_status(theirs, :inactive, admin, "Left")

      assert {:ok, _} =
               merge_accounts(mine.user, Accounts.get_user!(theirs.user_id))

      assert Members.get_member!(mine.id).status == :pending
      assert Members.get_member(mine.id).positions == []
      # Already inactive, so no further audit row is written about it.
      assert [%MembershipAudit{to_status: "inactive", reason: "Left"} | _] =
               Members.list_audit_for_member(theirs.id)
    end

    test "adopts the other profile when the survivor has none" do
      survivor = user_fixture()
      theirs = member_fixture(%{call_sign: "W2ADP"})

      assert {:ok, _} = merge_accounts(survivor, theirs.user)

      assert %Member{id: id, status: :approved, call_sign: "W2ADP"} =
               Members.get_member_by_user_id(survivor.id)

      assert id == theirs.id
      refute Members.get_member_by_user_id(theirs.user.id)

      assert [%MembershipAudit{from_status: "approved", to_status: "approved"} = audit | _] =
               Members.list_audit_for_member(theirs.id)

      assert audit.reason == "Moved from account #{theirs.user.email}"
    end

    test "merges an account that has no profile" do
      mine = member_fixture()
      other = user_fixture()

      assert {:ok, _} = merge_accounts(mine.user, other)
      assert Members.get_member!(mine.id).status == :approved
      assert Accounts.get_user!(other.id).deactivated_at
    end
  end
end

defmodule McEmcomm.MembersDeleteTest do
  use McEmcomm.DataCase, async: true

  import Mox

  alias McEmcomm.Certifications
  alias McEmcomm.Courses
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members
  alias McEmcomm.Net
  alias McEmcomm.Repo
  alias McEmcomm.Sightings
  alias McEmcomm.StorageMock

  setup :verify_on_exit!

  describe "delete_member/1 — cascade (§20)" do
    test "purges Tigris uploads, removes catalog join rows, de-links sightings and net_checkins" do
      member = McEmcommFixtures.member_fixture(%{call_sign: "W2DEL"})

      course = insert_course!()

      {:ok, _mc} =
        Courses.add_member_course(%{
          member_id: member.id,
          course_id: course.id,
          evidence_key: "member-uploads/evidence.pdf"
        })

      certification = insert_certification!()

      {:ok, _cert} =
        Certifications.add_member_certification(%{
          member_id: member.id,
          certification_id: certification.id,
          task_book_key: "member-uploads/task-book.pdf",
          certificate_key: "member-uploads/certificate.pdf"
        })

      asset = McEmcommFixtures.asset_fixture()

      {:ok, sighting} =
        Sightings.record_visit(%{
          asset_id: asset.id,
          session_token: "tok",
          visited_at: DateTime.utc_now()
        })

      {:ok, sighting} = Sightings.submit(sighting, %{"call_sign" => "W2DEL"})
      assert sighting.member_id == member.id

      other_member = McEmcommFixtures.member_fixture()
      {:ok, session} = Net.start_session(other_member, %{})
      {:ok, checkin} = Net.check_in(session, %{"call_sign" => "W2DEL"})
      assert checkin.member_id == member.id

      expect(StorageMock, :delete_object, 3, fn _key -> :ok end)

      assert {:ok, _} = Members.delete_member(member)

      assert Courses.list_member_courses(member.id) == []
      assert Certifications.list_member_certifications(member.id) == []

      reloaded_sighting = Sightings.get!(sighting.id)
      assert reloaded_sighting.member_id == nil

      reloaded_checkin = Repo.get!(McEmcomm.Net.NetCheckin, checkin.id)
      assert reloaded_checkin.member_id == nil
      assert reloaded_checkin.call_sign == "W2DEL"

      assert Members.list_audit_for_member(member.id) == []
      assert Repo.get(McEmcomm.Members.Member, member.id) == nil
      # The underlying user account is untouched.
      assert Repo.get(McEmcomm.Accounts.User, member.user_id)
    end

    test "refuses to delete a member who has started a net session" do
      member = McEmcommFixtures.member_fixture()
      {:ok, _session} = Net.start_session(member, %{})

      stub(StorageMock, :delete_object, fn _key -> :ok end)

      assert {:error, :has_started_net_sessions} = Members.delete_member(member)
      assert Repo.get(McEmcomm.Members.Member, member.id)
    end

    test "deleting a member who holds net control vacates the role" do
      starter = McEmcommFixtures.member_fixture()
      member = McEmcommFixtures.member_fixture()
      {:ok, session} = Net.start_session(starter, %{})
      {:ok, session} = Net.assign_net_control(session, member)
      assert session.net_control_member_id == member.id

      stub(StorageMock, :delete_object, fn _key -> :ok end)

      assert {:ok, _} = Members.delete_member(member)
      assert is_nil(Net.get_session!(session.id).net_control_member_id)
    end
  end

  defp insert_course! do
    {:ok, course} =
      Courses.create_course(%{name: "Delete Test Course #{System.unique_integer()}"})

    course
  end

  defp insert_certification! do
    {:ok, certification} =
      Certifications.create_certification(%{name: "Delete Test Cert #{System.unique_integer()}"})

    certification
  end
end

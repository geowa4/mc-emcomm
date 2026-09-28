defmodule McEmcomm.Members.DirectoryTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  @point %Geo.Point{coordinates: {-77.6088, 43.1566}, srid: 4326}

  defp member(name, call_sign, profile \\ %{}) do
    member = McEmcommFixtures.member_fixture(%{name: name, call_sign: call_sign})
    {:ok, updated} = Members.update_profile(member, profile)
    %{updated | user: member.user}
  end

  defp names(%{entries: entries}), do: Enum.map(entries, & &1.name)

  describe "list_directory/1" do
    test "lists approved members only" do
      approved = member("Avery Approved", "K2AAA")
      McEmcommFixtures.pending_member_fixture(%{name: "Parker Pending"})

      inactive = member("Indigo Inactive", "K2III")
      admin = McEmcommFixtures.admin_scope_fixture().user
      {:ok, _member} = Members.transition_status(inactive, :inactive, admin, "Moved away")

      assert %{entries: [entry], total_count: 1} = Members.list_directory()
      assert entry.id == approved.id
    end

    test "carries the directory fields and positions, and nothing else about a member" do
      member =
        member("Avery Approved", "K2AAA", %{
          license_class: :general,
          qth_point: @point,
          qth_address: "1 Main St",
          emergency_contact_name: "Casey Contact",
          emergency_contact_phone: "585-555-0100"
        })

      position = McEmcommFixtures.position_fixture(%{name: "Directory Steward"})
      {:ok, _member} = Members.assign_position(member, position)

      assert %{entries: [entry]} = Members.list_directory()
      assert entry.name == "Avery Approved"
      assert entry.call_sign == "K2AAA"
      assert entry.license_class == :general
      assert entry.qth_point == @point
      assert Enum.map(entry.positions, & &1.name) == ["Directory Steward"]
      assert entry.user.email == member.user.email

      assert entry.qth_address == nil
      assert entry.emergency_contact_name == nil
      assert entry.emergency_contact_phone == nil
    end

    test "carries nothing of the account but its primary email address" do
      member = member("Avery Approved", "K2AAA")
      user = member.user |> Ecto.Changeset.change(hashed_password: "hashed") |> Repo.update!()

      assert %{entries: [%{user: listed}]} = Members.list_directory()
      assert listed.email == user.email
      assert listed.hashed_password == nil
      assert listed.totp_secret == nil
      assert listed.is_admin == false
    end

    test "lists another status when asked, for administrators' tools" do
      member("Avery Approved", "K2AAA")
      pending = McEmcommFixtures.pending_member_fixture(%{name: "Parker Pending"})

      assert %{entries: [entry], total_count: 1} = Members.list_directory(status: :pending)
      assert entry.id == pending.id
      assert entry.status == :pending
    end

    test "searches the name and the call sign, ignoring case" do
      member("Avery Adams", "K2AAA")
      member("Blake Brown", "W2BBB")

      assert names(Members.list_directory(search: "avery")) == ["Avery Adams"]
      assert names(Members.list_directory(search: "w2b")) == ["Blake Brown"]
      assert names(Members.list_directory(search: "  BROWN ")) == ["Blake Brown"]
      assert names(Members.list_directory(search: "nobody")) == []
      assert names(Members.list_directory(search: "")) == ["Avery Adams", "Blake Brown"]
    end

    test "searches the primary email address, and never an additional one" do
      avery = member("Avery Adams", "K2AAA", %{qth_point: @point})
      member("Blake Brown", "W2BBB", %{qth_point: @point})

      {:ok, _email} =
        %McEmcomm.Accounts.UserEmail{user_id: avery.user.id}
        |> Ecto.Changeset.change(email: "hidden-alias@example.org")
        |> Repo.insert()

      assert names(Members.list_directory(search: String.upcase(avery.user.email))) ==
               ["Avery Adams"]

      assert names(Members.list_directory(search: "hidden-alias")) == []
      assert [%{name: "Avery Adams"}] = Members.list_directory_locations(search: avery.user.email)
    end

    test "treats the wildcard characters in a search literally" do
      member("Avery Adams", "K2AAA")

      assert names(Members.list_directory(search: "%")) == []
      assert names(Members.list_directory(search: "_")) == []
    end

    test "sorts by name or call sign in either direction" do
      member("Avery Adams", "W2ZZZ")
      member("Blake Brown", "K2AAA")
      member("Casey Clark", nil)

      assert names(Members.list_directory()) == ["Avery Adams", "Blake Brown", "Casey Clark"]

      assert names(Members.list_directory(sort: :name, direction: :desc)) ==
               ["Casey Clark", "Blake Brown", "Avery Adams"]

      assert names(Members.list_directory(sort: :call_sign)) ==
               ["Blake Brown", "Avery Adams", "Casey Clark"]

      # Members without a call sign stay at the end.
      assert names(Members.list_directory(sort: :call_sign, direction: :desc)) ==
               ["Avery Adams", "Blake Brown", "Casey Clark"]
    end

    test "falls back to name order for a sort it does not know" do
      member("Blake Brown", "K2AAA")
      member("Avery Adams", "W2ZZZ")

      assert names(Members.list_directory(sort: :status, direction: :sideways)) ==
               ["Avery Adams", "Blake Brown"]
    end

    test "pages the list" do
      for n <- 1..5, do: member("Member #{n}", "K2AA#{n}")

      first = Members.list_directory(per_page: 2)
      assert names(first) == ["Member 1", "Member 2"]
      assert %{page: 1, per_page: 2, total_count: 5, total_pages: 3} = first

      assert names(Members.list_directory(per_page: 2, page: 3)) == ["Member 5"]
    end

    test "answers a page outside the list with the nearest one" do
      for n <- 1..3, do: member("Member #{n}", "K2AA#{n}")

      assert %{page: 2} = last = Members.list_directory(per_page: 2, page: 9)
      assert names(last) == ["Member 3"]

      assert %{page: 1} = Members.list_directory(per_page: 2, page: 0)
      assert %{page: 1} = Members.list_directory(per_page: 2, page: nil)
    end

    test "is one empty page when nobody matches" do
      assert %{entries: [], page: 1, total_count: 0, total_pages: 1} = Members.list_directory()
    end
  end

  describe "list_directory_locations/1" do
    test "lists every approved member with a QTH point, regardless of paging" do
      for n <- 1..3, do: member("Member #{n}", "K2AA#{n}", %{qth_point: @point})
      member("No Location", "K2NNN")

      pending = McEmcommFixtures.pending_member_fixture(%{name: "Parker Pending"})
      {:ok, _member} = Members.update_profile(pending, %{qth_point: @point})

      located = Members.list_directory_locations()
      assert Enum.map(located, & &1.name) == ["Member 1", "Member 2", "Member 3"]
      assert Enum.all?(located, &(&1.qth_point == @point))
    end

    test "follows the search" do
      member("Avery Adams", "K2AAA", %{qth_point: @point})
      member("Blake Brown", "W2BBB", %{qth_point: @point})

      assert [%{name: "Blake Brown"}] = Members.list_directory_locations(search: "w2b")
    end
  end
end

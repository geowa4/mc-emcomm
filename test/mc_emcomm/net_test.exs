defmodule McEmcomm.NetTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.Locations
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members
  alias McEmcomm.Net

  describe "check-in location snapshots" do
    test "a matched member's QTH is snapshotted by default" do
      member = McEmcommFixtures.member_fixture(%{call_sign: "W2QTH"})
      point = McEmcommFixtures.geo_point(-77.7, 43.2)
      {:ok, _} = Members.update_profile(member, %{qth_point: point})

      starter = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(starter)

      {:ok, checkin} = Net.check_in(session, %{"call_sign" => "W2QTH"})
      assert checkin.location_name == "QTH"
      assert checkin.location_point.coordinates == point.coordinates
    end

    test "no location for an unmatched call sign or a member without a QTH point" do
      member = McEmcommFixtures.member_fixture(%{call_sign: "W2NOP"})
      starter = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(starter)

      {:ok, unmatched} = Net.check_in(session, %{"call_sign" => "W2XYZ"})
      assert is_nil(unmatched.location_name)
      assert is_nil(unmatched.location_point)

      {:ok, no_qth} = Net.check_in(session, %{"call_sign" => "W2NOP"})
      assert no_qth.member_id == member.id
      assert is_nil(no_qth.location_point)
    end

    test "a default location reference copies its name and point, surviving later edits" do
      location = McEmcommFixtures.default_location_fixture(%{name: "NW"})
      starter = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(starter)

      {:ok, checkin} =
        Net.check_in(session, %{
          "call_sign" => "W2ABC",
          "location_ref" => "default:#{location.id}"
        })

      assert checkin.location_name == "NW"
      assert checkin.location_point.coordinates == location.point.coordinates

      # The snapshot is a copy: editing the catalog entry leaves history alone.
      {:ok, _} =
        Locations.update_default_location(location, %{
          name: "Renamed",
          point: McEmcommFixtures.geo_point(-70.0, 40.0)
        })

      reloaded = Repo.get!(Net.NetCheckin, checkin.id)
      assert reloaded.location_name == "NW"
      assert reloaded.location_point.coordinates == location.point.coordinates
    end

    test "an unknown location reference yields no location" do
      starter = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(starter)

      {:ok, checkin} =
        Net.check_in(session, %{"call_sign" => "W2ABC", "location_ref" => "default:999999"})

      assert is_nil(checkin.location_name)
      assert is_nil(checkin.location_point)
    end

    test "an operation location is honored only for the session's operation" do
      operation = McEmcommFixtures.operation_fixture()
      [op_location] = operation.locations
      starter = McEmcommFixtures.member_fixture()

      plain = McEmcommFixtures.net_session_fixture(starter)

      {:ok, rejected} =
        Net.check_in(plain, %{"call_sign" => "W2ABC", "location_ref" => "op:#{op_location.id}"})

      assert is_nil(rejected.location_name)

      assigned =
        McEmcommFixtures.net_session_fixture(starter, %{"operation_id" => operation.id})

      {:ok, accepted} =
        Net.check_in(assigned, %{"call_sign" => "W2ABC", "location_ref" => "op:#{op_location.id}"})

      assert accepted.location_name == op_location.name
      assert accepted.location_point.coordinates == op_location.point.coordinates
    end

    test "update_checkin keeps, clears, or re-resolves the snapshot by ref" do
      member = McEmcommFixtures.member_fixture(%{call_sign: "W2QTH"})
      {:ok, _} = Members.update_profile(member, %{qth_point: McEmcommFixtures.geo_point()})
      location = McEmcommFixtures.default_location_fixture(%{name: "SE"})

      starter = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(starter)
      {:ok, checkin} = Net.check_in(session, %{"call_sign" => "W2QTH"})
      assert checkin.location_name == "QTH"

      # A blank ref keeps the current snapshot.
      {:ok, kept} = Net.update_checkin(session, checkin, %{"call_sign" => "W2QTH"})
      assert kept.location_name == "QTH"

      # A location ref replaces it.
      {:ok, relocated} =
        Net.update_checkin(session, checkin, %{
          "call_sign" => "W2QTH",
          "location_ref" => "default:#{location.id}"
        })

      assert relocated.location_name == "SE"

      # "qth" re-snapshots from the member profile; "none" clears it.
      {:ok, requeried} =
        Net.update_checkin(session, relocated, %{"call_sign" => "W2QTH", "location_ref" => "qth"})

      assert requeried.location_name == "QTH"

      {:ok, cleared} =
        Net.update_checkin(session, requeried, %{"call_sign" => "W2QTH", "location_ref" => "none"})

      assert is_nil(cleared.location_name)
      assert is_nil(cleared.location_point)
    end
  end

  describe "net control" do
    test "the starter is the initial net control operator" do
      starter = McEmcommFixtures.member_fixture()
      session = McEmcommFixtures.net_session_fixture(starter)
      assert session.net_control_member_id == starter.id
    end

    test "only approved members may be assigned" do
      starter = McEmcommFixtures.member_fixture()
      pending = McEmcommFixtures.pending_member_fixture()
      session = McEmcommFixtures.net_session_fixture(starter)

      assert {:error, :not_approved} = Net.assign_net_control(session, pending)

      approved = McEmcommFixtures.member_fixture()
      {:ok, session} = Net.assign_net_control(session, approved)
      assert session.net_control_member_id == approved.id
    end

    test "checking out the net control operator vacates the role; others do not" do
      starter = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
      other = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH"})
      session = McEmcommFixtures.net_session_fixture(starter)

      {:ok, other_checkin} = Net.check_in(session, %{"call_sign" => "W2OTH"})
      assert other_checkin.member_id == other.id

      {:ok, _} = Net.check_out(other_checkin)
      assert Net.get_session!(session.id).net_control_member_id == starter.id

      [ncs_checkin] =
        Enum.filter(Net.get_session!(session.id).checkins, &(&1.member_id == starter.id))

      {:ok, _} = Net.check_out(ncs_checkin)
      assert is_nil(Net.get_session!(session.id).net_control_member_id)
    end

    test "ending the net keeps the last net control operator on record" do
      starter = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
      session = McEmcommFixtures.net_session_fixture(starter)

      {:ok, _ended} = Net.end_session(session)
      assert Net.get_session!(session.id).net_control_member_id == starter.id
    end
  end

  describe "operation assignment" do
    test "assign_operation sets and clears the operation" do
      starter = McEmcommFixtures.member_fixture()
      operation = McEmcommFixtures.operation_fixture()
      session = McEmcommFixtures.net_session_fixture(starter)

      {:ok, session} = Net.assign_operation(session, operation.id)
      assert session.operation_id == operation.id
      assert [_location] = session.operation.locations

      {:ok, session} = Net.assign_operation(session, nil)
      assert is_nil(session.operation_id)
    end
  end
end

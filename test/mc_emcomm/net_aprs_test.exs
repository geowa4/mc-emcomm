defmodule McEmcomm.NetAprsTest do
  use McEmcomm.DataCase, async: true

  import Ecto.Query

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Net
  alias McEmcomm.Net.NetCheckin

  defp session_fixture(attrs \\ %{}) do
    starter = McEmcommFixtures.member_fixture()
    McEmcommFixtures.net_session_fixture(starter, attrs)
  end

  defp position(session, attrs) do
    McEmcommFixtures.aprs_position_fixture(Map.put_new(attrs, :comment, session.aprs_keyword))
  end

  defp open_checkins(session) do
    NetCheckin
    |> where([c], c.net_session_id == ^session.id and is_nil(c.ended_at))
    |> Repo.all()
  end

  describe "record_aprs_position/1 with the keyword" do
    test "checks an unknown station in as a guest at the reported position" do
      session = session_fixture()
      Net.subscribe(session.id)
      Net.subscribe_nets()
      point = McEmcommFixtures.geo_point(-77.5, 43.2)

      position =
        position(session, %{comment: "de W2XYZ #{session.aprs_keyword} mobile", point: point})

      assert {:ok, [checkin]} = Net.record_aprs_position(position)

      assert checkin.call_sign == "W2XYZ"
      assert checkin.aprs_call_sign == "W2XYZ-9"
      assert is_nil(checkin.member_id)
      assert checkin.location_name == "APRS"
      assert checkin.location_point.coordinates == point.coordinates
      assert is_nil(checkin.ended_at)
      assert_receive {:checkin_added, %NetCheckin{id: id}}
      assert id == checkin.id
      assert_receive {:nets_changed, :aprs_checkin}
    end

    test "matches the keyword case-insensitively" do
      session = session_fixture(%{"aprs_keyword" => "MCNet#{System.unique_integer([:positive])}"})

      assert {:ok, [_checkin]} =
               Net.record_aprs_position(
                 position(session, %{comment: String.downcase(session.aprs_keyword)})
               )
    end

    test "links a member by the base call sign, ignoring the SSID" do
      member = McEmcommFixtures.member_fixture(%{call_sign: "K4GWA"})
      session = session_fixture()

      assert {:ok, [checkin]} =
               Net.record_aprs_position(
                 position(session, %{station: "K4GWA-4", call_sign: "K4GWA", ssid: "4"})
               )

      assert checkin.member_id == member.id
      assert checkin.call_sign == "K4GWA"
      assert checkin.aprs_call_sign == "K4GWA-4"
    end

    test "moves a manual check-in for the same station instead of adding a row" do
      session = session_fixture()
      {:ok, manual} = Net.check_in(session, %{"call_sign" => "K4GWA"})
      Net.subscribe(session.id)
      Net.subscribe_nets()
      point = McEmcommFixtures.geo_point(-77.0, 43.0)

      assert {:ok, [moved]} =
               Net.record_aprs_position(
                 position(session, %{
                   station: "K4GWA-4",
                   call_sign: "K4GWA",
                   ssid: "4",
                   point: point
                 })
               )

      assert moved.id == manual.id
      assert moved.aprs_call_sign == "K4GWA-4"
      assert moved.location_name == "APRS"
      assert moved.location_point.coordinates == point.coordinates
      assert [_only] = open_checkins(session)
      assert_receive {:checkin_updated, %NetCheckin{id: id}}
      assert id == manual.id
      assert_receive {:nets_changed, :aprs_checkin}
    end

    test "routes to the net whose keyword the comment contains, or to both" do
      first = session_fixture()
      second = session_fixture()

      assert {:ok, [checkin]} = Net.record_aprs_position(position(first, %{}))
      assert checkin.net_session_id == first.id
      assert open_checkins(second) == []

      both = "#{first.aprs_keyword} and #{second.aprs_keyword}"

      other =
        McEmcommFixtures.aprs_position_fixture(%{
          station: "N2ABC",
          call_sign: "N2ABC",
          ssid: nil,
          comment: both
        })

      assert {:ok, touched} = Net.record_aprs_position(other)

      assert Enum.map(touched, & &1.net_session_id) |> Enum.sort() ==
               Enum.sort([first.id, second.id])
    end

    test "is idempotent for the same packet processed twice" do
      session = session_fixture()
      packet = position(session, %{})

      assert {:ok, [first]} = Net.record_aprs_position(packet)
      assert {:ok, [second]} = Net.record_aprs_position(packet)
      assert first.id == second.id
      assert [_only] = open_checkins(session)
    end
  end

  describe "record_aprs_position/1 without the keyword" do
    test "ignores stations that are not on any net" do
      session = session_fixture()
      Net.subscribe(session.id)

      assert {:ok, []} = Net.record_aprs_position(position(session, %{comment: "just driving"}))
      assert open_checkins(session) == []
      refute_receive {:checkin_added, _}
    end

    test "keeps moving a station APRS already placed until it leaves the net" do
      session = session_fixture()
      {:ok, [checkin]} = Net.record_aprs_position(position(session, %{}))
      Net.subscribe(session.id)
      moved_to = McEmcommFixtures.geo_point(-77.1, 43.1)

      assert {:ok, [moved]} =
               Net.record_aprs_position(position(session, %{comment: "", point: moved_to}))

      assert moved.id == checkin.id
      assert moved.location_point.coordinates == moved_to.coordinates
      assert_receive {:checkin_updated, %NetCheckin{id: id}}
      assert id == checkin.id

      {:ok, _left} = Net.check_out(moved)
      farther = McEmcommFixtures.geo_point(-77.2, 43.2)

      assert {:ok, []} =
               Net.record_aprs_position(position(session, %{comment: "", point: farther}))

      assert open_checkins(session) == []
      assert Repo.get!(NetCheckin, checkin.id).location_point.coordinates == moved_to.coordinates
    end

    test "ignores the operator's other SSIDs, such as a home station, until one sends the keyword" do
      session = session_fixture()
      mobile = McEmcommFixtures.geo_point(-77.5, 43.2)

      {:ok, [checkin]} =
        Net.record_aprs_position(
          position(session, %{station: "K4GWA-9", call_sign: "K4GWA", ssid: "9", point: mobile})
        )

      Net.subscribe(session.id)
      Net.subscribe_nets()
      home = McEmcommFixtures.geo_point(-77.0, 43.0)
      home_beacon = %{station: "K4GWA-1", call_sign: "K4GWA", ssid: "1", point: home}

      assert {:ok, []} =
               Net.record_aprs_position(position(session, Map.put(home_beacon, :comment, "")))

      assert Repo.get!(NetCheckin, checkin.id).location_point.coordinates == mobile.coordinates
      refute_receive {:checkin_updated, _}
      assert {_points, ["K4GWA-9"]} = Net.aprs_filter_inputs()

      # The home station sending the keyword takes over the operator's check-in.
      assert {:ok, [retargeted]} = Net.record_aprs_position(position(session, home_beacon))
      assert retargeted.id == checkin.id
      assert retargeted.aprs_call_sign == "K4GWA-1"
      assert retargeted.location_point.coordinates == home.coordinates
      assert_receive {:checkin_updated, %NetCheckin{aprs_call_sign: "K4GWA-1"}}
      assert_receive {:nets_changed, :aprs_checkin}
      assert {_points, ["K4GWA-1"]} = Net.aprs_filter_inputs()

      # And the mobile no longer moves the pin without the keyword.
      elsewhere = McEmcommFixtures.geo_point(-77.9, 43.9)

      assert {:ok, []} =
               Net.record_aprs_position(
                 position(session, %{
                   station: "K4GWA-9",
                   call_sign: "K4GWA",
                   ssid: "9",
                   point: elsewhere,
                   comment: ""
                 })
               )

      assert Repo.get!(NetCheckin, checkin.id).location_point.coordinates == home.coordinates
    end

    test "does nothing once the net has ended" do
      session = session_fixture()
      {:ok, [checkin]} = Net.record_aprs_position(position(session, %{}))
      {:ok, _ended} = Net.end_session(session)

      assert {:ok, []} = Net.record_aprs_position(position(session, %{}))
      assert {:ok, []} = Net.record_aprs_position(position(session, %{comment: ""}))
      assert Repo.aggregate(NetCheckin, :count) == 1
      refute is_nil(Repo.get!(NetCheckin, checkin.id).ended_at)
    end
  end

  describe "aprs_filter_inputs/0" do
    test "is empty with no active net" do
      session = session_fixture()
      {:ok, _ended} = Net.end_session(session)

      assert Net.aprs_filter_inputs() == {[], []}
    end

    test "covers default and operation locations plus tracked stations of active nets" do
      default = McEmcommFixtures.default_location_fixture()

      operation =
        McEmcommFixtures.operation_fixture(%{}, %{
          "point" => McEmcommFixtures.geo_point(-78.0, 42.0)
        })

      session = session_fixture(%{"operation_id" => operation.id})
      unlinked = session_fixture()
      ended = session_fixture()

      {:ok, [_tracked]} = Net.record_aprs_position(position(session, %{}))
      {:ok, _manual} = Net.check_in(unlinked, %{"call_sign" => "N2MAN"})

      {:ok, [left]} =
        Net.record_aprs_position(
          position(unlinked, %{station: "N2GONE", call_sign: "N2GONE", ssid: nil})
        )

      {:ok, _} = Net.check_out(left)

      {:ok, [_ended_tracked]} =
        Net.record_aprs_position(
          position(ended, %{station: "N2END", call_sign: "N2END", ssid: nil})
        )

      {:ok, _} = Net.end_session(ended)

      {points, stations} = Net.aprs_filter_inputs()

      coordinates = points |> Enum.map(& &1.coordinates) |> Enum.sort()
      assert coordinates == Enum.sort([default.point.coordinates, {-78.0, 42.0}])
      assert stations == ["W2XYZ-9"]
    end
  end

  describe "keywords" do
    test "are required, single words, and unique among active nets" do
      starter = McEmcommFixtures.member_fixture()

      assert {:error, changeset} = Net.start_session(starter, %{"name" => "No keyword"})
      assert %{aprs_keyword: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Net.start_session(starter, %{"name" => "Spaces", "aprs_keyword" => "two words"})

      assert %{aprs_keyword: ["can't contain spaces"]} = errors_on(changeset)

      session = McEmcommFixtures.net_session_fixture(starter)

      assert {:error, changeset} =
               Net.start_session(starter, %{
                 "name" => "Duplicate",
                 "aprs_keyword" => String.downcase(session.aprs_keyword)
               })

      assert %{aprs_keyword: ["is already used by an active net"]} = errors_on(changeset)

      {:ok, _ended} = Net.end_session(session)

      assert {:ok, _reused} =
               Net.start_session(starter, %{
                 "name" => "Reused",
                 "aprs_keyword" => session.aprs_keyword
               })
    end

    test "can be changed on an active net, subject to the same rules" do
      session = session_fixture()
      other = session_fixture()
      Net.subscribe(session.id)
      Net.subscribe_nets()

      assert {:error, changeset} = Net.update_aprs_keyword(session, other.aprs_keyword)
      assert %{aprs_keyword: ["is already used by an active net"]} = errors_on(changeset)

      assert {:ok, updated} = Net.update_aprs_keyword(session, "  fresh1 ")
      assert updated.aprs_keyword == "fresh1"
      assert_receive {:session_updated, %{aprs_keyword: "fresh1"}}
      assert_receive {:nets_changed, :keyword}
    end
  end

  test "net lifecycle changes are announced to APRS filter subscribers" do
    Net.subscribe_nets()
    starter = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(starter)
    assert_receive {:nets_changed, :session_started}

    {:ok, checkin} = Net.check_in(session, %{"call_sign" => "W2ABC"})
    {:ok, _} = Net.update_checkin(session, checkin, %{"notes" => "mobile"})
    assert_receive {:nets_changed, :checkin}

    {:ok, _} = Net.check_out(checkin)
    assert_receive {:nets_changed, :checkin}

    operation = McEmcommFixtures.operation_fixture()
    {:ok, _} = Net.assign_operation(session, operation.id)
    assert_receive {:nets_changed, :operation}

    {:ok, _} = Net.end_session(session)
    assert_receive {:nets_changed, :session_ended}
  end
end

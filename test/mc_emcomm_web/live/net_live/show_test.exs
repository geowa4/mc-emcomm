defmodule McEmcommWeb.NetLive.ShowTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  test "checking in adds to the roster and broadcasts to other viewers", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    other_member = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH"})

    {:ok, _} =
      McEmcomm.Members.update_profile(other_member, %{qth_point: McEmcommFixtures.geo_point()})

    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    lv
    |> form("#checkin-form", net_checkin: %{call_sign: "w2oth", notes: "loud and clear"})
    |> render_submit()

    assert render(lv) =~ "W2OTH"
    # The matched member's QTH is snapshotted as the check-in's location.
    assert has_element?(lv, "#checkins td", "QTH")
    # The on-net map carries a marker for the operator.
    assert has_element?(lv, "#net-map[data-markers*='W2OTH']")
    # The submitter's client is told to clear the form and refocus the call sign.
    assert_push_event(lv, "checkin_saved", %{})
    # The second viewer receives the check-in over PubSub without resubmitting.
    assert render(other_lv) =~ "W2OTH"
    assert has_element?(other_lv, "#net-map[data-markers*='W2OTH']")
  end

  test "checking in with a default location snapshots its name and point", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    location = McEmcommFixtures.default_location_fixture(%{name: "NW"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")
    assert has_element?(lv, "#checkin-location option[value='default:#{location.id}']")

    lv
    |> form("#checkin-form", %{
      "net_checkin" => %{"call_sign" => "W2OTH"},
      "location_ref" => "default:#{location.id}"
    })
    |> render_submit()

    [checkin] = checkins_for(session.id, "W2OTH")
    assert checkin.location_name == "NW"
    assert checkin.location_point.coordinates == location.point.coordinates
    assert has_element?(lv, "#net-map[data-markers*='NW']")
  end

  test "operation locations are selectable only when the net has that operation", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    operation = McEmcommFixtures.operation_fixture()
    [op_location] = operation.locations

    plain_session = McEmcommFixtures.net_session_fixture(member)
    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{plain_session.id}")
    refute has_element?(lv, "#checkin-location option[value='op:#{op_location.id}']")

    op_session =
      McEmcommFixtures.net_session_fixture(member, %{"operation_id" => operation.id})

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{op_session.id}")
    assert has_element?(lv, "#checkin-location option[value='op:#{op_location.id}']")

    lv
    |> form("#checkin-form", %{
      "net_checkin" => %{"call_sign" => "W2OTH"},
      "location_ref" => "op:#{op_location.id}"
    })
    |> render_submit()

    [checkin] = checkins_for(op_session.id, "W2OTH")
    assert checkin.location_name == op_location.name
  end

  test "the starter is shown as net control and any member can take or vacate it", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO", name: "Starter Member"})
    other_member = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH", name: "Other Member"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")
    assert has_element?(lv, "#net-control", "Starter Member")
    # The current net control operator has no take button.
    refute has_element?(lv, "#take-net-control")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    # The other viewer takes net control; both pages update over PubSub.
    other_lv |> element("#take-net-control") |> render_click()
    assert has_element?(other_lv, "#net-control", "Other Member")
    assert has_element?(lv, "#net-control", "Other Member")

    # The take button swaps sides with the role.
    refute has_element?(other_lv, "#take-net-control")
    assert has_element?(lv, "#take-net-control")

    # Vacating shows the role as vacant everywhere.
    lv |> element("#vacate-net-control") |> render_click()
    assert has_element?(lv, "#net-control", "Vacant")
    assert has_element?(other_lv, "#net-control", "Vacant")
  end

  test "net control can be reassigned through the change modal", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    other_member = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH", name: "Other Member"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    lv |> element("#change-net-control") |> render_click()
    assert has_element?(lv, "#ncs-modal")

    lv |> form("#ncs-search-form", %{"call_sign" => "W2OTH"}) |> render_submit()
    assert has_element?(lv, "#ncs-results", "W2OTH")

    lv |> element("#ncs-results button", "Other Member") |> render_click()
    refute has_element?(lv, "#ncs-modal")
    assert has_element?(lv, "#net-control", "Other Member")
    assert McEmcomm.Net.get_session!(session.id).net_control_member_id == other_member.id
  end

  test "net control is vacated when its operator leaves the net", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    [checkin] = checkins_for(session.id, "W2NCO")
    lv |> element("#checkout-checkin-#{checkin.id}") |> render_click()

    assert has_element?(lv, "#net-control", "Vacant")
    assert is_nil(McEmcomm.Net.get_session!(session.id).net_control_member_id)
    # The marker for the departed operator leaves the map.
    refute has_element?(lv, "#net-map[data-markers*='W2NCO']")
  end

  test "a net can be assigned to an operation from its page", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    operation = McEmcommFixtures.operation_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()
    other_member = McEmcommFixtures.member_fixture()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    lv |> element("#edit-net-operation") |> render_click()
    assert has_element?(lv, "#net-operation-form")

    lv
    |> form("#net-operation-form", %{"operation_id" => to_string(operation.id)})
    |> render_submit()

    assert has_element?(lv, "#net-operation", operation.title)
    assert McEmcomm.Net.get_session!(session.id).operation_id == operation.id
    # The other viewer sees the assignment over PubSub.
    assert has_element?(other_lv, "#net-operation", operation.title)

    # Clearing the assignment.
    lv |> element("#edit-net-operation") |> render_click()
    lv |> form("#net-operation-form", %{"operation_id" => ""}) |> render_submit()
    assert has_element?(lv, "#net-operation", "None")
    assert is_nil(McEmcomm.Net.get_session!(session.id).operation_id)
  end

  test "editing a check-in can change its location snapshot", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    location = McEmcommFixtures.default_location_fixture(%{name: "SE"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    [checkin] = checkins_for(session.id, "W2NCO")
    assert is_nil(checkin.location_name)

    lv |> element("#edit-checkin-#{checkin.id}") |> render_click()
    assert has_element?(lv, "#edit-checkin-location")

    lv
    |> form("#edit-checkin-form", %{
      "net_checkin" => %{"call_sign" => "W2NCO"},
      "location_ref" => "default:#{location.id}"
    })
    |> render_submit()

    [checkin] = checkins_for(session.id, "W2NCO")
    assert checkin.location_name == "SE"
    assert checkin.location_point.coordinates == location.point.coordinates
  end

  test "renaming a net via the pencil updates the name for other viewers", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    other_member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    lv |> element("#edit-net-name") |> render_click()
    assert has_element?(lv, "#net-name-form")

    lv |> form("#net-name-form", net_session: %{name: "Severe Weather Net"}) |> render_submit()

    refute has_element?(lv, "#net-name-form")
    assert render(lv) =~ "Severe Weather Net"
    # The second viewer sees the rename over PubSub.
    assert render(other_lv) =~ "Severe Weather Net"
  end

  test "cancelling a rename keeps the current name", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    lv |> element("#edit-net-name") |> render_click()
    lv |> element("button", "Cancel") |> render_click()

    refute has_element?(lv, "#net-name-form")
    assert render(lv) =~ session.name
  end

  test "ending a net removes the check-in form", %{conn: conn} do
    member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")
    assert html =~ "checkin-form"

    html = lv |> element("button", "End net") |> render_click()
    refute html =~ "checkin-form"
  end

  test "editing a check-in corrects it for other viewers and re-links the member", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    other_member = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    # Mistyped call sign, matching no member.
    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2OTX"}) |> render_submit()

    [checkin] = checkins_for(session.id, "W2OTX")
    assert is_nil(checkin.member_id)

    lv |> element("#edit-checkin-#{checkin.id}") |> render_click()
    assert has_element?(lv, "#edit-checkin-form")

    lv
    |> form("#edit-checkin-form", net_checkin: %{call_sign: "w2oth", notes: "corrected"})
    |> render_submit()

    refute has_element?(lv, "#edit-checkin-form")
    assert render(lv) =~ "W2OTH"
    assert render(lv) =~ "corrected"
    # The correction re-links the member record by call sign.
    [checkin] = checkins_for(session.id, "W2OTH")
    assert checkin.member_id == other_member.id
    # The second viewer receives the correction over PubSub.
    assert render(other_lv) =~ "W2OTH"
  end

  test "clicking the modal backdrop cancels the check-in edit", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    [checkin] = checkins_for(session.id, "W2NCO")
    lv |> element("#edit-checkin-#{checkin.id}") |> render_click()
    assert has_element?(lv, "#edit-checkin-modal")

    lv |> element("#edit-checkin-modal .modal-backdrop") |> render_click()
    refute has_element?(lv, "#edit-checkin-modal")
  end

  test "leaving logs an end time and checking back in adds a new roster entry", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2OTH"}) |> render_submit()

    [checkin] = checkins_for(session.id, "W2OTH")
    lv |> element("#checkout-checkin-#{checkin.id}") |> render_click()

    [checkin] = checkins_for(session.id, "W2OTH")
    assert checkin.ended_at
    # The ended check-in no longer offers a leave button.
    refute has_element?(lv, "#checkout-checkin-#{checkin.id}")

    # Coming back later is a fresh check-in; the earlier stint stays logged.
    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2OTH"}) |> render_submit()

    checkins = checkins_for(session.id, "W2OTH")
    assert length(checkins) == 2
    assert has_element?(lv, "#checkin-row-#{checkin.id}")
    [returned] = Enum.reject(checkins, &(&1.id == checkin.id))
    assert is_nil(returned.ended_at)
    assert has_element?(lv, "#checkout-checkin-#{returned.id}")
  end

  test "ending the net ends every open check-in", %{conn: conn} do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NCO"})
    other_member = McEmcommFixtures.member_fixture(%{call_sign: "W2OTH"})
    session = McEmcommFixtures.net_session_fixture(member)

    {:ok, lv, _html} = conn |> log_in_user(member.user) |> live(~p"/app/net/#{session.id}")

    other_conn = Phoenix.ConnTest.build_conn()

    {:ok, other_lv, _html} =
      other_conn |> log_in_user(other_member.user) |> live(~p"/app/net/#{session.id}")

    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2NCO"}) |> render_submit()
    lv |> form("#checkin-form", net_checkin: %{call_sign: "W2OTH"}) |> render_submit()

    lv |> element("button", "End net") |> render_click()

    reloaded = McEmcomm.Net.get_session!(session.id)
    assert reloaded.ended_at

    for checkin <- reloaded.checkins do
      assert DateTime.compare(checkin.ended_at, reloaded.ended_at) == :eq
    end

    # Other viewers see the ended net without any leave buttons left.
    refute has_element?(other_lv, "#checkin-form")
    refute render(other_lv) =~ "checkout-checkin-"
  end

  defp checkins_for(session_id, call_sign) do
    for c <- McEmcomm.Net.get_session!(session_id).checkins, c.call_sign == call_sign, do: c
  end
end

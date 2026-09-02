defmodule McEmcomm.Net do
  @moduledoc """
  The live net logger: sessions and check-ins, broadcast over Phoenix PubSub
  to a live map and roster.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Locations
  alias McEmcomm.Locations.DefaultLocation
  alias McEmcomm.Members.Member
  alias McEmcomm.Net.NetCheckin
  alias McEmcomm.Net.NetSession
  alias McEmcomm.Operations.OperationLocation
  alias McEmcomm.Repo

  @pubsub McEmcomm.PubSub
  @nets_topic "nets"

  def topic(net_session_id), do: "net_session:#{net_session_id}"

  def subscribe(net_session_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(net_session_id))
  end

  @doc """
  Subscribes to `{:nets_changed, reason}`, sent whenever the set of active
  nets, their keywords or operations, or their open check-ins change: the
  inputs of the APRS-IS filter (`aprs_filter_inputs/0`).
  """
  def subscribe_nets, do: Phoenix.PubSub.subscribe(@pubsub, @nets_topic)

  defp broadcast(net_session_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(net_session_id), message)
  end

  defp broadcast_nets_changed(reason) do
    Phoenix.PubSub.broadcast(@pubsub, @nets_topic, {:nets_changed, reason})
  end

  defp notify_nets_changed({:ok, _} = result, reason) do
    broadcast_nets_changed(reason)
    result
  end

  defp notify_nets_changed(error, _reason), do: error

  ## Sessions

  def list_sessions do
    NetSession
    |> order_by([n], desc: n.started_at)
    |> preload(:started_by_member)
    |> Repo.all()
  end

  def list_active_sessions do
    NetSession
    |> where([n], is_nil(n.ended_at))
    |> order_by([n], desc: n.started_at)
    |> Repo.all()
  end

  def list_past_sessions do
    NetSession
    |> where([n], not is_nil(n.ended_at))
    |> order_by([n], desc: n.started_at)
    |> preload(:started_by_member)
    |> Repo.all()
  end

  def get_session!(id) do
    NetSession
    |> Repo.get!(id)
    |> Repo.preload([:net_control_member, operation: :locations, checkins: :member])
  end

  def change_session(%NetSession{} = session, attrs \\ %{}) do
    NetSession.changeset(session, attrs)
  end

  @doc """
  Any approved member may start a net session, optionally assigning it to an
  operation. A session without a name is named after its start date. The
  operator calling the net is on frequency from the start, so they are logged
  as its first check-in and become the initial net control operator.
  """
  def start_session(%Member{status: :approved} = member, attrs) do
    started_at = DateTime.utc_now()

    attrs =
      attrs
      |> Map.merge(%{"started_by_member_id" => member.id, "started_at" => started_at})
      |> put_default_name(started_at)

    %NetSession{}
    |> NetSession.changeset(attrs)
    |> Ecto.Changeset.put_change(:net_control_member_id, member.id)
    |> Repo.insert()
    |> case do
      {:ok, session} = result ->
        check_in_net_control(session, member)
        broadcast_nets_changed(:session_started)
        result

      error ->
        error
    end
  end

  # A member without a call sign can still run a net; they just don't appear
  # in the roster automatically.
  defp check_in_net_control(session, %Member{call_sign: call_sign})
       when is_binary(call_sign) and call_sign != "" do
    {:ok, _checkin} = check_in(session, %{"call_sign" => call_sign})
    :ok
  end

  defp check_in_net_control(_session, _member), do: :ok

  defp put_default_name(attrs, started_at) do
    case attrs["name"] do
      name when is_binary(name) and name != "" -> attrs
      _ -> Map.put(attrs, "name", started_at |> DateTime.to_date() |> Date.to_string())
    end
  end

  @doc """
  Ends the session and closes every still-active check-in at the same instant,
  so no check-in outlives its net.
  """
  def end_session(%NetSession{} = session) do
    changeset = NetSession.end_changeset(session)

    result =
      Repo.transaction(fn ->
        case Repo.update(changeset) do
          {:ok, ended} ->
            NetCheckin
            |> where([c], c.net_session_id == ^ended.id and is_nil(c.ended_at))
            |> Repo.update_all(set: [ended_at: ended.ended_at])

            ended

          {:error, error_changeset} ->
            Repo.rollback(error_changeset)
        end
      end)

    with {:ok, ended} <- result do
      broadcast(ended.id, {:session_ended, ended})
      broadcast_nets_changed(:session_ended)
      {:ok, ended}
    end
  end

  def rename_session(%NetSession{} = session, name) do
    session
    |> NetSession.changeset(%{"name" => name})
    |> Repo.update()
    |> case do
      {:ok, renamed} = result ->
        broadcast(renamed.id, {:session_renamed, renamed})
        result

      error ->
        error
    end
  end

  @doc "Changes the word stations beacon to check in; must be unique among active nets."
  def update_aprs_keyword(%NetSession{} = session, keyword) do
    session
    |> NetSession.aprs_keyword_changeset(keyword)
    |> Repo.update()
    |> broadcast_session_updated()
    |> notify_nets_changed(:keyword)
  end

  ## Check-ins

  def change_checkin(%NetCheckin{} = checkin, attrs \\ %{}) do
    NetCheckin.changeset(checkin, attrs)
  end

  @doc """
  Records a check-in, auto-linking by call sign and snapshotting a location:
  by default the matched member's QTH, or the default/operation location named
  by `"location_ref"` (`"default:ID"` / `"op:ID"`, resolved server-side). An
  operator who left the net and comes back checks in again: each stint is its
  own row, so the log keeps every join/leave with its duration.
  """
  def check_in(%NetSession{} = session, attrs) do
    call_sign = attrs["call_sign"] || attrs[:call_sign]
    matched_member = match_member(call_sign)

    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    attrs =
      attrs
      |> Map.put("net_session_id", session.id)
      |> Map.put("member_id", matched_member && matched_member.id)
      |> Map.put("recorded_at", DateTime.utc_now())
      |> Map.merge(resolve_location(attrs["location_ref"], matched_member, session))

    %NetCheckin{}
    |> NetCheckin.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, checkin} = result ->
        checkin = Repo.preload(checkin, :member)
        broadcast(session.id, {:checkin_added, checkin})
        result

      error ->
        error
    end
  end

  @doc """
  Corrects a check-in. A present, non-blank `"location_ref"` re-resolves the
  location snapshot (`"qth"`, `"none"`, `"default:ID"`, `"op:ID"`); a blank or
  absent ref keeps the existing snapshot.
  """
  def update_checkin(%NetSession{} = session, %NetCheckin{} = checkin, attrs) do
    changeset = NetCheckin.update_changeset(checkin, attrs)

    changeset =
      case Ecto.Changeset.fetch_change(changeset, :call_sign) do
        {:ok, call_sign} ->
          matched_member = match_member(call_sign)
          Ecto.Changeset.put_change(changeset, :member_id, matched_member && matched_member.id)

        :error ->
          changeset
      end

    changeset
    |> apply_location_ref(attrs["location_ref"], session)
    |> Repo.update()
    |> broadcast_checkin_change()
    |> notify_nets_changed(:checkin)
  end

  @doc """
  Logs the operator leaving the net; the check-in keeps its start and end
  times. If the operator was net control, the role becomes vacant.
  """
  def check_out(%NetCheckin{ended_at: nil} = checkin, ended_at \\ DateTime.utc_now()) do
    checkin
    |> NetCheckin.end_changeset(ended_at)
    |> Repo.update()
    |> case do
      {:ok, checkin} ->
        maybe_vacate_net_control(checkin)
        broadcast_checkin_change({:ok, checkin})

      error ->
        error
    end
    |> notify_nets_changed(:checkin)
  end

  ## APRS positions

  @doc """
  What the APRS-IS filter must cover: every default location plus the
  locations of each active net's operation, and the exact station ids (with
  SSID) APRS has already placed in an active net, so their beacons keep
  arriving wherever they go. `{[], []}` when no net is active.
  """
  @spec aprs_filter_inputs() :: {[Geo.Point.t()], [String.t()]}
  def aprs_filter_inputs do
    case Repo.preload(list_active_sessions(), operation: :locations) do
      [] ->
        {[], []}

      sessions ->
        default_points = Enum.map(Locations.list_default_locations(), & &1.point)

        operation_points =
          for session <- sessions,
              session.operation,
              location <- session.operation.locations,
              do: location.point

        {default_points ++ operation_points, list_aprs_tracked_stations()}
    end
  end

  # Exact station ids, SSID included: an operator's home station and mobile
  # beacon under different SSIDs, and only the one that sent the keyword may
  # move the pin.
  defp list_aprs_tracked_stations do
    NetCheckin
    |> join(:inner, [c], s in assoc(c, :net_session))
    |> where([c, s], is_nil(s.ended_at) and is_nil(c.ended_at) and not is_nil(c.aprs_call_sign))
    |> distinct(true)
    |> select([c], c.aprs_call_sign)
    |> Repo.all()
  end

  @doc """
  Applies one APRS position report to every active net. A comment containing
  a net's keyword checks the station in, or moves the operator's open check-in
  there and makes this station (call sign plus SSID) the one being tracked; the
  tracked station keeps moving the pin without the keyword until the operator
  leaves or the net ends. Beacons from the operator's other SSIDs, such as a
  home station, are ignored unless they send the keyword themselves. Returns
  the check-ins touched.

  Each net is handled in its own transaction under a row lock on the session,
  so two app instances receiving the same packet (blue-green overlap) or a
  packet racing `end_session/1` converge on one row and never revive an ended
  net.
  """
  @spec record_aprs_position(McEmcomm.Aprs.Packet.position()) :: {:ok, [NetCheckin.t()]}
  def record_aprs_position(%{
        station: station,
        call_sign: call_sign,
        point: point,
        comment: comment
      }) do
    comment = String.downcase(comment)

    touched =
      Enum.flat_map(list_active_sessions(), fn session ->
        keyword? = String.contains?(comment, String.downcase(session.aprs_keyword))
        record_aprs_position_in(session, call_sign, station, point, keyword?)
      end)

    {:ok, touched}
  end

  defp record_aprs_position_in(session, call_sign, station, point, keyword?) do
    case apply_aprs_position(session.id, call_sign, station, point, keyword?) do
      {:ok, {outcome, checkin}} ->
        checkin = Repo.preload(checkin, :member)
        broadcast(session.id, {aprs_outcome_message(outcome), checkin})
        if outcome in [:inserted, :tracked], do: broadcast_nets_changed(:aprs_checkin)
        [checkin]

      {:error, _reason} ->
        []
    end
  end

  defp apply_aprs_position(session_id, call_sign, station, point, keyword?) do
    Repo.transaction(fn ->
      session =
        NetSession
        |> where([s], s.id == ^session_id and is_nil(s.ended_at))
        |> lock("FOR UPDATE")
        |> Repo.one()

      open = session && open_checkin(session_id, call_sign)

      case {session, open, keyword?} do
        {nil, _open, _keyword?} ->
          Repo.rollback(:ended)

        # The station already tracked moves the pin, keyword or not.
        {_session, %NetCheckin{aprs_call_sign: ^station} = open, _keyword?} ->
          {:moved, move_aprs_checkin(open, station, point)}

        # The keyword from a manual check-in's operator, or from another of
        # their SSIDs, hands tracking to this station.
        {_session, %NetCheckin{} = open, true} ->
          {:tracked, move_aprs_checkin(open, station, point)}

        {session, nil, true} ->
          {:inserted, insert_aprs_checkin(session, call_sign, station, point)}

        _no_match ->
          Repo.rollback(:no_match)
      end
    end)
  end

  defp open_checkin(session_id, call_sign) do
    NetCheckin
    |> where([c], c.net_session_id == ^session_id and c.call_sign == ^call_sign)
    |> where([c], is_nil(c.ended_at))
    |> order_by([c], desc: c.recorded_at)
    |> limit(1)
    |> Repo.one()
  end

  defp move_aprs_checkin(checkin, station, point) do
    checkin |> NetCheckin.aprs_position_changeset(station, point) |> Repo.update!()
  end

  defp insert_aprs_checkin(session, call_sign, station, point) do
    matched_member = match_member(call_sign)

    %NetCheckin{}
    |> NetCheckin.changeset(%{
      "net_session_id" => session.id,
      "call_sign" => call_sign,
      "member_id" => matched_member && matched_member.id,
      "recorded_at" => DateTime.utc_now(),
      "location_name" => "APRS",
      "location_point" => point
    })
    |> Ecto.Changeset.put_change(:aprs_call_sign, station)
    |> Repo.insert!()
  end

  defp aprs_outcome_message(:inserted), do: :checkin_added
  defp aprs_outcome_message(_moved_or_tracked), do: :checkin_updated

  ## Net control

  def assign_net_control(%NetSession{} = session, %Member{status: :approved} = member) do
    set_net_control(session, member.id)
  end

  def assign_net_control(%NetSession{}, %Member{}), do: {:error, :not_approved}

  def vacate_net_control(%NetSession{} = session), do: set_net_control(session, nil)

  defp set_net_control(session, member_id_or_nil) do
    session
    |> NetSession.net_control_changeset(member_id_or_nil)
    |> Repo.update()
    |> broadcast_session_updated()
  end

  defp maybe_vacate_net_control(%NetCheckin{member_id: member_id} = checkin)
       when not is_nil(member_id) do
    session = Repo.get!(NetSession, checkin.net_session_id)

    if is_nil(session.ended_at) and session.net_control_member_id == member_id do
      {:ok, _session} = vacate_net_control(session)
    end

    :ok
  end

  defp maybe_vacate_net_control(_checkin), do: :ok

  @doc "Assigns the session to an operation, or clears the assignment with `nil`."
  def assign_operation(%NetSession{} = session, operation_id_or_nil) do
    session
    |> NetSession.operation_changeset(operation_id_or_nil)
    |> Repo.update()
    |> broadcast_session_updated()
    |> notify_nets_changed(:operation)
  end

  defp broadcast_session_updated({:ok, session}) do
    session = get_session!(session.id)
    broadcast(session.id, {:session_updated, session})
    {:ok, session}
  end

  defp broadcast_session_updated(error), do: error

  defp broadcast_checkin_change({:ok, checkin}) do
    checkin = Repo.preload(checkin, :member, force: true)
    broadcast(checkin.net_session_id, {:checkin_updated, checkin})
    {:ok, checkin}
  end

  defp broadcast_checkin_change(error), do: error

  defp match_member(call_sign) when is_binary(call_sign) do
    Repo.get_by(Member, call_sign: normalize(call_sign))
  end

  defp match_member(_call_sign), do: nil

  defp normalize(call_sign), do: call_sign |> String.trim() |> String.upcase()

  ## Location snapshot resolution
  #
  # References come from the client but are resolved server-side; an unknown id
  # or an operation location outside the session's operation yields no location.

  defp apply_location_ref(changeset, ref, _session) when ref in [nil, ""], do: changeset

  defp apply_location_ref(changeset, ref, session) do
    member =
      case Ecto.Changeset.get_field(changeset, :member_id) do
        nil -> nil
        member_id -> Repo.get(Member, member_id)
      end

    %{"location_name" => name, "location_point" => point} =
      resolve_location(ref, member, session)

    changeset
    |> Ecto.Changeset.put_change(:location_name, name)
    |> Ecto.Changeset.put_change(:location_point, point)
  end

  defp resolve_location(ref, member, _session) when ref in [nil, "", "qth"] do
    qth_snapshot(member)
  end

  defp resolve_location("default:" <> id, _member, _session) do
    with {int, ""} <- Integer.parse(id),
         %DefaultLocation{} = location <- Repo.get(DefaultLocation, int) do
      %{"location_name" => location.name, "location_point" => location.point}
    else
      _ -> empty_location()
    end
  end

  defp resolve_location("op:" <> id, _member, %NetSession{operation_id: operation_id})
       when not is_nil(operation_id) do
    with {int, ""} <- Integer.parse(id),
         %OperationLocation{operation_id: ^operation_id} = location <-
           Repo.get(OperationLocation, int) do
      %{"location_name" => location.name, "location_point" => location.point}
    else
      _ -> empty_location()
    end
  end

  defp resolve_location(_ref, _member, _session), do: empty_location()

  defp qth_snapshot(%Member{qth_point: %Geo.Point{} = point}) do
    %{"location_name" => "QTH", "location_point" => point}
  end

  defp qth_snapshot(_member), do: empty_location()

  defp empty_location, do: %{"location_name" => nil, "location_point" => nil}
end

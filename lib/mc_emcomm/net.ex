defmodule McEmcomm.Net do
  @moduledoc """
  The live net logger: sessions and check-ins, broadcast over Phoenix PubSub
  to a live map and roster.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Members.Member
  alias McEmcomm.Net.NetCheckin
  alias McEmcomm.Net.NetSession
  alias McEmcomm.Repo

  @pubsub McEmcomm.PubSub

  def topic(net_session_id), do: "net_session:#{net_session_id}"

  def subscribe(net_session_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(net_session_id))
  end

  defp broadcast(net_session_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(net_session_id), message)
  end

  ## Sessions

  def list_sessions do
    NetSession
    |> order_by([n], desc: n.started_at)
    |> preload(:started_by_member)
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
    NetSession |> Repo.get!(id) |> Repo.preload(checkins: :member)
  end

  def change_session(%NetSession{} = session, attrs \\ %{}) do
    NetSession.changeset(session, attrs)
  end

  @doc """
  Any approved member may start a net session. A session without a name is
  named after its start date.
  """
  def start_session(%Member{status: :approved} = member, attrs) do
    started_at = DateTime.utc_now()

    attrs =
      attrs
      |> Map.merge(%{"started_by_member_id" => member.id, "started_at" => started_at})
      |> put_default_name(started_at)

    %NetSession{}
    |> NetSession.changeset(attrs)
    |> Repo.insert()
  end

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

  ## Check-ins

  def change_checkin(%NetCheckin{} = checkin, attrs \\ %{}) do
    NetCheckin.changeset(checkin, attrs)
  end

  @doc """
  Records a check-in, auto-linking by call sign and prefilling quadrant from the
  member. An operator who left the net and comes back checks in again: each
  stint is its own row, so the log keeps every join/leave with its duration.
  """
  def check_in(%NetSession{} = session, attrs) do
    call_sign = attrs["call_sign"] || attrs[:call_sign]
    matched_member = match_member(call_sign)

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("net_session_id", session.id)
      |> Map.put("member_id", matched_member && matched_member.id)
      |> Map.put("recorded_at", DateTime.utc_now())
      |> maybe_prefill_quadrant(matched_member)

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

  def update_checkin(%NetCheckin{} = checkin, attrs) do
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
    |> Repo.update()
    |> broadcast_checkin_change()
  end

  @doc "Logs the operator leaving the net; the check-in keeps its start and end times."
  def check_out(%NetCheckin{ended_at: nil} = checkin, ended_at \\ DateTime.utc_now()) do
    checkin
    |> NetCheckin.end_changeset(ended_at)
    |> Repo.update()
    |> broadcast_checkin_change()
  end

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

  defp maybe_prefill_quadrant(%{"quadrant" => quadrant} = attrs, _member)
       when quadrant not in [nil, ""],
       do: attrs

  defp maybe_prefill_quadrant(attrs, %Member{quadrant: quadrant}) when not is_nil(quadrant),
    do: Map.put(attrs, "quadrant", quadrant)

  defp maybe_prefill_quadrant(attrs, _member), do: attrs
end

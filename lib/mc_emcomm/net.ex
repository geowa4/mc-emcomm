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

  def end_session(%NetSession{} = session) do
    session |> NetSession.end_changeset() |> Repo.update()
  end

  ## Check-ins

  def change_checkin(%NetCheckin{} = checkin, attrs \\ %{}) do
    NetCheckin.changeset(checkin, attrs)
  end

  @doc "Records a check-in, auto-linking by call sign and prefilling quadrant from the member."
  def check_in(%NetSession{} = session, attrs) do
    call_sign = attrs["call_sign"] || attrs[:call_sign]
    matched_member = call_sign && Repo.get_by(Member, call_sign: normalize(call_sign))

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

  defp normalize(call_sign), do: call_sign |> String.trim() |> String.upcase()

  defp maybe_prefill_quadrant(%{"quadrant" => quadrant} = attrs, _member)
       when quadrant not in [nil, ""],
       do: attrs

  defp maybe_prefill_quadrant(attrs, %Member{quadrant: quadrant}) when not is_nil(quadrant),
    do: Map.put(attrs, "quadrant", quadrant)

  defp maybe_prefill_quadrant(attrs, _member), do: attrs
end

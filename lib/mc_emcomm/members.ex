defmodule McEmcomm.Members do
  @moduledoc """
  Member profiles and the membership approval state machine.

  States: `pending`, `approved`, `rejected`, `inactive`. Legal transitions:
  `pending -> approved`, `pending -> rejected`, `approved <-> inactive`,
  `rejected -> pending`. Every transition is admin-only and writes a
  `membership_audit` row; `reason` is required transitioning `-> rejected`
  or `-> inactive`.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Accounts.User
  alias McEmcomm.Certifications
  alias McEmcomm.Courses
  alias McEmcomm.Members.Member
  alias McEmcomm.Members.MemberPosition
  alias McEmcomm.Members.MembershipAudit
  alias McEmcomm.Members.Position
  alias McEmcomm.Repo
  alias McEmcomm.Storage

  @legal_transitions %{
    "pending" => ["approved", "rejected"],
    "approved" => ["inactive"],
    "rejected" => ["pending"],
    "inactive" => ["approved"]
  }

  @reason_required_statuses ["rejected", "inactive"]

  def legal_transitions, do: @legal_transitions

  @doc "Returns the member for the given user, or nil."
  def get_member_by_user_id(user_id) do
    Repo.get_by(Member, user_id: user_id)
  end

  def get_member!(id), do: Repo.get!(Member, id)

  @doc """
  True when the member currently holds at least one leadership position
  whose `grants_admin` flag is set. Position-derived admin access follows
  the holder: it appears when the position is assigned and disappears when
  the position is vacated or reassigned.
  """
  def holds_admin_position?(member_id) do
    Repo.exists?(
      from mp in MemberPosition,
        join: p in Position,
        on: p.id == mp.position_id,
        where: mp.member_id == ^member_id and p.grants_admin
    )
  end

  @doc "Creates the member profile row for a newly registered user (status: pending)."
  def create_member(attrs) do
    %Member{}
    |> Member.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_profile(%Member{} = member, attrs \\ %{}) do
    Member.profile_changeset(member, attrs)
  end

  def update_profile(%Member{} = member, attrs) do
    member
    |> Member.profile_changeset(attrs)
    |> Repo.update()
  end

  def list_members(opts \\ []) do
    Member
    |> maybe_filter_status(opts[:status])
    |> order_by([m], asc: m.name)
    |> preload(positions: ^positions_query())
    |> Repo.all()
  end

  def list_pending_members do
    list_members(status: :pending)
  end

  @doc """
  Every leadership position in display order, each with its approved
  holders preloaded — used to render leadership on the public About page,
  where an unfilled position still appears (as vacant). Pass `holders: :all`
  to include non-approved holders (the admin positions page).
  """
  def list_positions(opts \\ []) do
    holders =
      case opts[:holders] do
        :all -> from m in Member, order_by: m.name
        _ -> from m in Member, where: m.status == :approved, order_by: m.name
      end

    Position
    |> order_by([p], asc: p.sort_order)
    |> preload(members: ^holders)
    |> Repo.all()
  end

  @doc """
  Approved members whose call sign contains the given letters,
  case-insensitively, ordered by call sign (at most 10) — only approved
  members can be assigned a position. A blank query matches nobody.
  """
  def search_members_by_call_sign(partial) when is_binary(partial) do
    case String.trim(partial) do
      "" ->
        []

      term ->
        pattern =
          "%" <>
            (term
             |> String.replace("\\", "\\\\")
             |> String.replace("%", "\\%")
             |> String.replace("_", "\\_")) <> "%"

        Member
        |> where([m], m.status == :approved)
        |> where([m], ilike(m.call_sign, ^pattern))
        |> order_by([m], asc: m.call_sign)
        |> limit(10)
        |> Repo.all()
    end
  end

  @doc """
  Makes the member the holder of the position, keeping their other
  positions and taking the position over from any current holder. Only
  approved members can hold positions (`{:error, :not_approved}`).
  """
  def assign_position(%Member{} = member, %Position{} = position) do
    current_ids =
      member
      |> Repo.preload(:positions)
      |> Map.fetch!(:positions)
      |> Enum.map(& &1.id)

    update_member_positions(member, Enum.uniq([position.id | current_ids]))
  end

  @doc "Removes the position from whoever holds it, leaving it vacant."
  def vacate_position(%Position{} = position) do
    Repo.delete_all(from mp in MemberPosition, where: mp.position_id == ^position.id)
    :ok
  end

  def get_position!(id), do: Repo.get!(Position, id)

  def change_position(%Position{} = position, attrs \\ %{}) do
    Position.changeset(position, attrs)
  end

  def create_position(attrs) do
    %Position{} |> Position.changeset(attrs) |> Repo.insert()
  end

  def update_position(%Position{} = position, attrs) do
    position |> Position.changeset(attrs) |> Repo.update()
  end

  @doc """
  Deletes a position unless a member currently holds it, in which case
  `{:error, :position_held}` is returned — the admin must vacate it first.
  """
  def delete_position(%Position{} = position) do
    held? = Repo.exists?(from mp in MemberPosition, where: mp.position_id == ^position.id)

    if held? do
      {:error, :position_held}
    else
      Repo.delete(position)
    end
  end

  @doc "The sort_order after the current last position, for prefilling the new-position form."
  def next_position_sort_order do
    (Repo.aggregate(Position, :max, :sort_order) || 0) + 1
  end

  @doc """
  Renumbers every position's sort_order to match the given id order (1..n).
  The ids must be exactly the current position ids — a drag reorder from a
  stale list returns `{:error, :stale}` and changes nothing.
  """
  def reorder_positions(ids) do
    current_ids = Repo.all(from p in Position, select: p.id)

    if Enum.sort(ids) == Enum.sort(current_ids) do
      {:ok, :ok} = Repo.transaction(fn -> renumber_positions(ids) end)
      :ok
    else
      {:error, :stale}
    end
  end

  defp renumber_positions(ids) do
    # Shift everything out of the way first so the intermediate states
    # never violate the unique index on sort_order.
    Repo.update_all(from(p in Position, where: p.id in ^ids), inc: [sort_order: 1_000_000])

    ids
    |> Enum.with_index(1)
    |> Enum.each(fn {id, index} ->
      Repo.update_all(from(p in Position, where: p.id == ^id), set: [sort_order: index])
    end)
  end

  @doc """
  Replaces a member's leadership positions with the given position ids,
  admin-only. Every position is single-holder: assigning a position another
  member holds takes it over, removing it from that member. A member with no
  positions is an ordinary member; a member may hold several positions.

  Only approved members may gain positions — `{:error, :not_approved}`
  otherwise. Removing positions is allowed regardless of status, as
  defense in depth (leaving approved status already vacates a member's
  positions).
  """
  def update_member_positions(%Member{} = member, position_ids) do
    current_ids =
      member
      |> Repo.preload(:positions)
      |> Map.fetch!(:positions)
      |> Enum.map(& &1.id)

    if member.status != :approved and position_ids -- current_ids != [] do
      {:error, :not_approved}
    else
      do_update_member_positions(member, position_ids)
    end
  end

  defp do_update_member_positions(member, position_ids) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete_all(
      :taken_over,
      from(mp in MemberPosition,
        where: mp.position_id in ^position_ids and mp.member_id != ^member.id
      )
    )
    |> Ecto.Multi.update(:member, fn _changes ->
      positions = Repo.all(from p in Position, where: p.id in ^position_ids)

      member
      |> Repo.preload(:positions)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:positions, positions)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{member: member}} -> {:ok, member}
      {:error, _step, error, _changes} -> {:error, error}
    end
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [m], m.status == ^status)

  defp positions_query, do: from(p in Position, order_by: p.sort_order)

  @doc """
  Transitions a member's status, admin-only, writing a `membership_audit`
  row. Returns `{:error, :illegal_transition}` for a transition not in
  `legal_transitions/0`, or `{:error, changeset}` if `reason` is missing for
  a transition into `rejected`/`inactive`.
  """
  @spec transition_status(Member.t(), String.t() | atom(), User.t(), String.t() | nil) ::
          {:ok, Member.t()} | {:error, :illegal_transition | Ecto.Changeset.t()}
  def transition_status(%Member{} = member, to_status, %User{} = actor, reason \\ nil) do
    from_status = to_string(member.status)
    to_status = to_string(to_status)

    if to_status in Map.get(@legal_transitions, from_status, []) do
      do_transition(member, from_status, to_status, actor, reason)
    else
      {:error, :illegal_transition}
    end
  end

  defp do_transition(member, from_status, to_status, actor, reason) do
    audit_attrs = %{
      member_id: member.id,
      actor_user_id: actor.id,
      from_status: from_status,
      to_status: to_status,
      reason: reason
    }

    audit_changeset = MembershipAudit.changeset(%MembershipAudit{}, audit_attrs)
    member_changeset = Member.status_changeset(member, String.to_existing_atom(to_status))

    Ecto.Multi.new()
    |> Ecto.Multi.update(:member, member_changeset)
    |> Ecto.Multi.insert(:audit, audit_changeset)
    |> vacate_positions_unless_approved(member, to_status)
    |> Repo.transaction()
    |> case do
      {:ok, %{member: member}} -> {:ok, member}
      {:error, :member, changeset, _} -> {:error, changeset}
      {:error, :audit, changeset, _} -> {:error, changeset}
    end
  end

  # Only approved members may hold positions, so leaving approved vacates
  # every position the member holds (and with it any position-derived
  # admin access).
  defp vacate_positions_unless_approved(multi, _member, "approved"), do: multi

  defp vacate_positions_unless_approved(multi, member, _to_status) do
    Ecto.Multi.delete_all(
      multi,
      :positions,
      from(mp in MemberPosition, where: mp.member_id == ^member.id)
    )
  end

  def reason_required?(to_status), do: to_string(to_status) in @reason_required_statuses

  def list_audit_for_member(member_id) do
    MembershipAudit
    |> where([a], a.member_id == ^member_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Deletes a member's profile and cascades sensibly (§20): purges their
  Tigris uploads (course evidence, task books, certificates), then deletes
  the `members` row. Everything else is handled declaratively by each FK's
  `on_delete` (membership_audit rows go with them; sightings are de-linked;
  `net_checkins` keep the call sign text with the member link nulled).
  The underlying `users` account is untouched — `membership_audit.actor_user_id`
  must keep resolving for audit rows on *other* members.

  Returns `{:error, :has_started_net_sessions}` if the member has started a
  net session (net history is kept intact rather than orphaned).
  """
  @spec delete_member(Member.t()) ::
          {:ok, Member.t()} | {:error, :has_started_net_sessions | Ecto.Changeset.t()}
  def delete_member(%Member{} = member) do
    purge_uploads(member)

    member
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(:started_net_sessions,
      message: "has started net sessions and cannot be deleted"
    )
    |> Repo.delete()
    |> case do
      {:ok, member} -> {:ok, member}
      {:error, changeset} -> delete_error(changeset)
    end
  end

  defp delete_error(changeset) do
    if Keyword.has_key?(changeset.errors, :started_net_sessions) do
      {:error, :has_started_net_sessions}
    else
      {:error, changeset}
    end
  end

  defp purge_uploads(member) do
    member.id
    |> Courses.list_member_courses()
    |> Enum.each(fn mc -> mc.evidence_key && Storage.delete_object(mc.evidence_key) end)

    member.id
    |> Certifications.list_member_certifications()
    |> Enum.each(fn mc ->
      mc.task_book_key && Storage.delete_object(mc.task_book_key)
      mc.certificate_key && Storage.delete_object(mc.certificate_key)
    end)
  end
end

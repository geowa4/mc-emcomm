defmodule McEmcomm.Members do
  @moduledoc """
  Member profiles and the membership approval state machine.

  States: `pending`, `approved`, `rejected`, `inactive`. Legal transitions:
  `pending -> approved`, `pending -> rejected`, `approved <-> inactive`,
  `rejected -> pending`. Every transition is admin-only and writes a
  `membership_audit` row; `reason` is required transitioning `-> rejected`
  or `-> inactive`.

  An administrator can also invite a member by email (`invite_member/2`),
  which creates the account and an already-approved profile.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Accounts.User
  alias McEmcomm.Certifications
  alias McEmcomm.Courses
  alias McEmcomm.Members.Member
  alias McEmcomm.Members.MemberNotifier
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

  @invitation_types %{email: :string, name: :string, call_sign: :string}
  @invitation_reason "Invited by an administrator"

  def legal_transitions, do: @legal_transitions

  @doc "Returns the member for the given user, or nil."
  def get_member_by_user_id(user_id) do
    Repo.get_by(Member, user_id: user_id)
  end

  def get_member!(id), do: Repo.get!(Member, id)

  @doc "Like `get_member!/1` but `nil` for an unknown id, with positions preloaded."
  def get_member(id) do
    case Repo.get(Member, id) do
      nil -> nil
      member -> Repo.preload(member, positions: positions_query())
    end
  end

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

  @doc """
  Users who should hear about a newly registered member: the approved holders
  of every position whose `notify_on_new_member` flag is set, each listed once
  even when they hold several flagged positions.
  """
  def list_new_member_notification_recipients do
    Repo.all(
      from u in User,
        join: m in Member,
        on: m.user_id == u.id,
        join: mp in MemberPosition,
        on: mp.member_id == m.id,
        join: p in Position,
        on: p.id == mp.position_id,
        where: p.notify_on_new_member and m.status == :approved,
        distinct: true,
        order_by: u.email
    )
  end

  @doc """
  Emails the recipients above about the member profile belonging to `user`,
  who has just registered. The address is not yet confirmed at this point;
  leadership hears about every signup, including ones that never confirm.
  Recipients are resolved here, synchronously; delivery runs under
  `McEmcomm.TaskSupervisor` so a mail outage can never fail the registration.
  A user with no member profile, or an empty recipient list, is a no-op.
  """
  @spec notify_new_member_registered(User.t()) :: :ok
  def notify_new_member_registered(%User{} = user) do
    with %Member{} = member <- get_member_by_user_id(user.id),
         [_ | _] = recipients <- list_new_member_notification_recipients() do
      {:ok, _pid} =
        Task.Supervisor.start_child(McEmcomm.TaskSupervisor, fn ->
          {:ok, _emails} = MemberNotifier.deliver_new_member_notice(member, user, recipients)
        end)

      :ok
    else
      _ -> :ok
    end
  end

  @doc "Creates the member profile row for a newly registered user (status: pending)."
  def create_member(attrs) do
    %Member{}
    |> Member.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "A schemaless changeset over the invitation form: email, name, optional call sign."
  def change_invitation(attrs \\ %{}) do
    {%{}, @invitation_types}
    |> Ecto.Changeset.cast(attrs, Map.keys(@invitation_types))
    |> Ecto.Changeset.validate_required([:email, :name])
  end

  @doc """
  Invites a member by email, admin-only: creates the `users` row (no
  password, unconfirmed), an `approved` member profile, and a
  `membership_audit` row (`pending -> approved`, written by `actor`) in one
  transaction, then emails the invitation. The invitee still proves they own
  the address by confirming through a login link before any session exists.

  Leadership is not sent the new-member notice, and the invitation replaces
  the approval email.

  An address whose account has a `pending` profile is approved instead,
  through `transition_status/4`: the member keeps the name and call sign they
  registered with and gets the usual approval email. Any other address that
  already has an account is refused with "has already been taken".

  Errors come back on the `change_invitation/1` changeset so a form can show
  them against the field the admin typed.
  """
  @spec invite_member(map(), User.t()) :: {:ok, Member.t()} | {:error, Ecto.Changeset.t()}
  def invite_member(attrs, %User{} = actor) do
    invitation = change_invitation(attrs)

    if invitation.valid? do
      data = Ecto.Changeset.apply_changes(invitation)

      case pending_member_by_email(data.email) do
        %Member{} = pending -> approve_invited(pending, invitation, actor)
        nil -> create_invited(data, invitation, actor)
      end
    else
      {:error, %{invitation | action: :insert}}
    end
  end

  defp pending_member_by_email(email) do
    Repo.one(
      from m in Member,
        join: u in User,
        on: u.id == m.user_id,
        where: u.email == ^email and m.status == :pending
    )
  end

  defp approve_invited(pending, invitation, actor) do
    case transition_status(pending, :approved, actor, @invitation_reason) do
      {:ok, member} -> {:ok, member}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, copy_errors(invitation, changeset)}
    end
  end

  defp create_invited(data, invitation, actor) do
    case insert_invited_member(data, actor) do
      {:ok, %{user: user, member: member}} ->
        notify_member_invited(member, user)
        {:ok, member}

      {:error, _step, changeset, _changes} ->
        {:error, copy_errors(invitation, changeset)}
    end
  end

  defp insert_invited_member(invitation, actor) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.email_changeset(%User{}, %{email: invitation.email}))
    |> Ecto.Multi.insert(:member, fn %{user: user} ->
      Member.invitation_changeset(
        %Member{user_id: user.id, status: :approved},
        Map.take(invitation, [:name, :call_sign])
      )
    end)
    |> Ecto.Multi.insert(:audit, fn %{member: member} ->
      MembershipAudit.changeset(%MembershipAudit{}, %{
        member_id: member.id,
        actor_user_id: actor.id,
        from_status: "pending",
        to_status: "approved",
        reason: @invitation_reason
      })
    end)
    |> Repo.transaction()
  end

  defp copy_errors(invitation, %Ecto.Changeset{errors: errors}) do
    Enum.reduce(errors, %{invitation | action: :insert}, fn {field, {message, opts}}, acc ->
      Ecto.Changeset.add_error(acc, field, message, opts)
    end)
  end

  # Delivery runs under `McEmcomm.TaskSupervisor` so a mail outage can never
  # fail the invitation that was already committed.
  defp notify_member_invited(%Member{} = member, %User{} = user) do
    {:ok, _pid} =
      Task.Supervisor.start_child(McEmcomm.TaskSupervisor, fn ->
        {:ok, _email} = MemberNotifier.deliver_invitation(member, user)
      end)

    :ok
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
        pattern = contains_pattern(term)

        Member
        |> where([m], m.status == :approved)
        |> where([m], ilike(m.call_sign, ^pattern))
        |> order_by([m], asc: m.call_sign)
        |> limit(10)
        |> Repo.all()
    end
  end

  # An ILIKE pattern matching anything that contains `term` literally.
  defp contains_pattern(term) do
    "%" <>
      (term
       |> String.replace("\\", "\\\\")
       |> String.replace("%", "\\%")
       |> String.replace("_", "\\_")) <> "%"
  end

  @directory_fields [:id, :user_id, :name, :call_sign, :license_class, :qth_point, :status]
  @directory_sorts [:name, :call_sign]
  @directory_per_page 25
  @directory_search_max_length 100

  @doc "The columns the member directory can be sorted by."
  def directory_sorts, do: @directory_sorts

  @doc """
  One page of the member directory (§30): approved members only, carrying
  just the fields the directory shows (#{Enum.map_join(@directory_fields, ", ", &"`#{&1}`")}),
  their positions, and the primary email address of their account (on
  `user`, which carries nothing but `id` and `email`), so nothing else about
  a member reaches the page.

  Options:

    * `:status` — the membership status to list, `:approved` by default.
      Any other status is for administrators; the caller is responsible
      for having checked that.
    * `:search` — letters the name, call sign, or primary email address
      must contain, case-insensitively; blank matches everyone. Additional
      addresses (§29) are not shown, so they are not searched either: a
      match would give one away.
    * `:sort` — `:name` (default) or `:call_sign`; members without a call
      sign come last either way
    * `:direction` — `:asc` (default) or `:desc`
    * `:page` — 1-based; a page past the end is answered with the last page
    * `:per_page` — defaults to #{@directory_per_page}

  Anything else given for `:sort` or `:direction` falls back to the default.
  """
  @spec list_directory(keyword()) :: %{
          entries: [Member.t()],
          page: pos_integer(),
          per_page: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: pos_integer()
        }
  def list_directory(opts \\ []) do
    per_page = opts[:per_page] || @directory_per_page
    query = directory_query(opts[:search], opts[:status])

    total_count = Repo.aggregate(query, :count)
    total_pages = max(1, ceil(total_count / per_page))
    page = (opts[:page] || 1) |> max(1) |> min(total_pages)

    entries =
      query
      |> order_by(^directory_order(opts[:sort], opts[:direction]))
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> select([m], struct(m, ^@directory_fields))
      |> preload(positions: ^positions_query(), user: ^directory_user_query())
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @doc """
  Every approved member matching `:search` who has set a QTH point, by name,
  for the directory map (§30). Unlike `list_directory/1` this is not paged:
  the map shows everyone the search matches.
  """
  @spec list_directory_locations(keyword()) :: [Member.t()]
  def list_directory_locations(opts \\ []) do
    opts[:search]
    |> directory_query(:approved)
    |> where([m], not is_nil(m.qth_point))
    |> order_by([m], asc: m.name, asc: m.id)
    |> select([m], struct(m, [:id, :name, :call_sign, :qth_point]))
    |> Repo.all()
  end

  # `approved` is written into the query, rather than bound, so the planner
  # can match it to the partial `members_directory_name_index`.
  defp directory_query(search, status) when status in [nil, :approved] do
    Member
    |> where([m], m.status == :approved)
    |> filter_directory_search(search)
  end

  defp directory_query(search, status) when status in [:pending, :rejected, :inactive] do
    Member
    |> where([m], m.status == ^status)
    |> filter_directory_search(search)
  end

  defp directory_user_query, do: from(u in User, select: struct(u, [:id, :email]))

  defp filter_directory_search(query, search) when is_binary(search) do
    case search |> String.trim() |> String.slice(0, @directory_search_max_length) do
      "" ->
        query

      term ->
        pattern = contains_pattern(term)

        query
        |> join(:inner, [m], u in assoc(m, :user), as: :user)
        |> where(
          [m, user: u],
          ilike(m.name, ^pattern) or ilike(m.call_sign, ^pattern) or ilike(u.email, ^pattern)
        )
    end
  end

  defp filter_directory_search(query, _search), do: query

  # The id breaks ties in the direction of the sort, so the name order can be
  # read straight off `members_directory_name_index` in either direction.
  defp directory_order(:call_sign, :desc), do: [desc_nulls_last: :call_sign, desc: :id]
  defp directory_order(:call_sign, _direction), do: [asc_nulls_last: :call_sign, asc: :id]
  defp directory_order(_sort, :desc), do: [desc: :name, desc: :id]
  defp directory_order(_sort, _direction), do: [asc: :name, asc: :id]

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
      {:ok, %{member: member}} ->
        if to_status == "approved", do: notify_membership_approved(member)
        {:ok, member}

      {:error, :member, changeset, _} ->
        {:error, changeset}

      {:error, :audit, changeset, _} ->
        {:error, changeset}
    end
  end

  # Tells the member their membership is approved (first approval and
  # reactivation alike). Delivery runs under `McEmcomm.TaskSupervisor` so a
  # mail outage can never fail the transition that was already committed.
  defp notify_membership_approved(%Member{} = member) do
    case Repo.get(User, member.user_id) do
      %User{} = user ->
        {:ok, _pid} =
          Task.Supervisor.start_child(McEmcomm.TaskSupervisor, fn ->
            {:ok, _email} = MemberNotifier.deliver_membership_approved(member, user)
          end)

        :ok

      nil ->
        :ok
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

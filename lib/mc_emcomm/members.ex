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
  alias McEmcomm.Members.MembershipAudit
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

  def change_role(%Member{} = member, attrs) do
    Member.role_changeset(member, attrs)
  end

  def update_role(%Member{} = member, attrs) do
    member
    |> Member.role_changeset(attrs)
    |> Repo.update()
  end

  def list_members(opts \\ []) do
    Member
    |> maybe_filter_status(opts[:status])
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end

  def list_pending_members do
    list_members(status: :pending)
  end

  @doc """
  Members whose role is not the default `:member` — used to render
  leadership on the public About page.
  """
  def list_leadership do
    Member
    |> where([m], m.role != :member and m.status == :approved)
    |> order_by([m], asc: m.role)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [m], m.status == ^status)

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

    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :member,
      Member.status_changeset(member, String.to_existing_atom(to_status))
    )
    |> Ecto.Multi.insert(:audit, audit_changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{member: member}} -> {:ok, member}
      {:error, :member, changeset, _} -> {:error, changeset}
      {:error, :audit, changeset, _} -> {:error, changeset}
    end
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

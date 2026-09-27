defmodule McEmcomm.AccountMerge do
  @moduledoc """
  Merges two accounts that belong to the same person (SPEC.md §29).

  A merge starts when a user asks to add an email address that already
  belongs to another account and then follows the link mailed to that
  address (`McEmcomm.Accounts.deliver_additional_email_instructions/3`). The
  link proves they can read that mailbox, which is what a magic-link login
  to the other account would have asked of them.

  The logged-in account is the *survivor*; the account that held the address
  is the *other* one. `plan/2` describes what a merge would do, for the
  review page; `merge/3` does it in one transaction:

    * profile details and training records the user ticked on the review
      page are copied or moved to the survivor's member profile;
    * activity (attendance, RSVPs, sightings, net check-ins, nets started or
      controlled) moves to the survivor's profile;
    * the survivor inherits the other account's standing: an approved
      membership, its leadership positions, and the admin flag;
    * everything that recorded the other user as its author is re-pointed;
    * the other account's email addresses become the survivor's;
    * the other account is deactivated: sessions, login tokens, OAuth grants,
      and password are removed, and its member profile goes `inactive`.

  An account protected by two-factor authentication cannot be absorbed:
  reading its mail is not enough to log in to it, so it is not enough to
  merge it either.
  """

  import Ecto.Query

  alias McEmcomm.Accounts
  alias McEmcomm.Accounts.{RecoveryCode, User, UserEmail, UserToken}
  alias McEmcomm.Capabilities.MemberCapability
  alias McEmcomm.Certifications.MemberCertification
  alias McEmcomm.Courses.MemberCourse
  alias McEmcomm.Members
  alias McEmcomm.Members.{Member, MemberPosition, MembershipAudit, Position}
  alias McEmcomm.Net.{NetCheckin, NetSession}
  alias McEmcomm.OAuth
  alias McEmcomm.Operations.{Operation, OperationAttachment, OperationAttendance, OperationRsvp}
  alias McEmcomm.Repo
  alias McEmcomm.Sightings.Sighting
  alias McEmcomm.Storage

  @typedoc """
  One thing the review page offers to bring over. `mine` is what the
  survivor has today (nil when nothing); ticking the item replaces it with
  `theirs`. `default` is the suggested choice: bring over what fills a gap,
  keep what the survivor already has.
  """
  @type item :: %{
          required(:key) => String.t(),
          optional(:id) => integer(),
          required(:group) => :profile | :capabilities | :courses | :certifications,
          required(:label) => String.t(),
          required(:mine) => String.t() | nil,
          required(:theirs) => String.t(),
          required(:default) => boolean()
        }

  @type plan :: %{
          other: User.t(),
          blocked: nil | :two_factor,
          survivor_member: Member.t() | nil,
          other_member: Member.t() | nil,
          adopts_profile?: boolean(),
          items: [item()],
          gains: %{approved?: boolean(), positions: [Position.t()], admin?: boolean()}
        }

  @emergency_contact_fields [
    :emergency_contact_name,
    :emergency_contact_phone,
    :emergency_contact_relation
  ]

  # What each profile item copies. Fields that only make sense together
  # travel together.
  @profile_fields [
    {"name", "Name", [:name]},
    {"call_sign", "Call sign", [:call_sign]},
    {"license_class", "License class", [:license_class]},
    {"qth", "Home location (QTH)", [:qth_address, :qth_point]},
    {"emergency_contact", "Emergency contact", @emergency_contact_fields}
  ]

  @doc """
  Describes what merging `other` into `survivor` would do.
  """
  @spec plan(User.t(), User.t()) :: plan()
  def plan(%User{} = survivor, %User{} = other) do
    survivor_member = Members.get_member_by_user_id(survivor.id)
    other_member = Members.get_member_by_user_id(other.id)

    %{
      other: other,
      blocked: if(Accounts.totp_enabled?(other), do: :two_factor),
      survivor_member: survivor_member,
      other_member: other_member,
      adopts_profile?: is_nil(survivor_member) and not is_nil(other_member),
      items: items(survivor_member, other_member),
      gains: gains(survivor, survivor_member, other, other_member)
    }
  end

  @doc """
  Merges the account that holds the claimed address into `survivor`.

  `token` is the add-email token from the link; `selected_keys` are the
  `key`s of the plan items the user ticked (unknown keys are ignored).

  Returns the reloaded survivor and the other account's session tokens, so
  the caller can disconnect its LiveViews. Errors: `:invalid` for a bad,
  expired, or somebody else's token, or when the address no longer belongs
  to another account; `:two_factor` when the other account has two-factor
  authentication on.
  """
  @spec merge(User.t(), String.t(), [String.t()]) ::
          {:ok, %{user: User.t(), expired_tokens: [UserToken.t()]}}
          | {:error, :invalid | :two_factor}
  def merge(%User{} = survivor, token, selected_keys)
      when is_binary(token) and is_list(selected_keys) do
    result =
      Repo.transact(fn ->
        with {:ok, claim} <- Accounts.fetch_email_claim(survivor, token),
             {:ok, survivor, other} <- lock_accounts(survivor, claim.sent_to),
             plan = plan(survivor, other),
             :ok <- check_unblocked(plan) do
          run(plan, survivor, claim, MapSet.new(selected_keys))
        end
      end)

    with {:ok, %{purge: keys} = merged} <- result do
      Enum.each(keys, &Storage.delete_object/1)
      {:ok, Map.delete(merged, :purge)}
    end
  end

  # Both rows are locked, in id order, so two merges touching the same
  # account run one after the other rather than interleaving.
  defp lock_accounts(survivor, email) do
    case Accounts.get_user_by_email(email) do
      %User{id: other_id} when other_id != survivor.id ->
        ids = [survivor.id, other_id]

        users =
          Repo.all(
            from u in User,
              where: u.id in ^ids and is_nil(u.deactivated_at),
              order_by: u.id,
              lock: "FOR UPDATE"
          )

        case {Enum.find(users, &(&1.id == survivor.id)), Enum.find(users, &(&1.id == other_id))} do
          {%User{} = survivor, %User{} = other} -> {:ok, survivor, other}
          _ -> {:error, :invalid}
        end

      _ ->
        {:error, :invalid}
    end
  end

  defp check_unblocked(%{blocked: nil}), do: :ok
  defp check_unblocked(%{blocked: reason}), do: {:error, reason}

  defp run(plan, survivor, claim, selected) do
    other = plan.other

    with {:ok, purge} <- merge_profiles(plan, survivor, selected),
         {:ok, expired_tokens} <- absorb_account(survivor, other),
         {:ok, survivor} <- inherit_admin(survivor, other) do
      Accounts.delete_email_claims(survivor, claim.sent_to)
      {:ok, %{user: survivor, expired_tokens: expired_tokens, purge: purge}}
    end
  end

  ## Member profiles

  defp merge_profiles(%{other_member: nil}, _survivor, _selected), do: {:ok, []}

  # The survivor has no profile of their own, so the other account's profile
  # simply becomes theirs, standing and history included.
  defp merge_profiles(%{adopts_profile?: true} = plan, survivor, _selected) do
    member = plan.other_member
    status = to_string(member.status)

    with {:ok, _member} <- member |> Ecto.Changeset.change(user_id: survivor.id) |> Repo.update(),
         {:ok, _audit} <-
           audit(member, survivor, status, status, "Moved from account #{plan.other.email}") do
      {:ok, []}
    end
  end

  defp merge_profiles(plan, survivor, selected) do
    %{survivor_member: mine, other_member: theirs} = plan
    chosen = Enum.filter(plan.items, &MapSet.member?(selected, &1.key))

    with {:ok, mine} <- copy_profile_fields(mine, theirs, chosen),
         purge = move_training(mine, theirs, chosen),
         :ok <- move_activity(mine, theirs),
         {:ok, mine} <- inherit_standing(plan, mine, survivor),
         {:ok, _theirs} <- retire_member(plan, survivor) do
      move_or_vacate_positions(mine, theirs)
      {:ok, purge}
    end
  end

  defp copy_profile_fields(mine, theirs, chosen) do
    fields =
      for %{group: :profile, key: key} <- chosen,
          {^key, _label, fields} <- @profile_fields,
          field <- fields,
          do: field

    # The call sign is unique, so the other profile lets go of it first.
    if :call_sign in fields do
      Repo.update_all(from(m in Member, where: m.id == ^theirs.id), set: [call_sign: nil])
    end

    mine
    |> Ecto.Changeset.change(Map.take(theirs, fields))
    |> Ecto.Changeset.unique_constraint(:call_sign, name: :members_call_sign_index)
    |> Repo.update()
  end

  # Moves the chosen training records, replacing the survivor's own record of
  # the same course or certification. Returns the storage keys of the files
  # that belonged to the replaced records, to purge once the merge commits.
  defp move_training(mine, theirs, chosen) do
    Enum.flat_map(chosen, fn
      %{group: :capabilities, id: id} ->
        move_record(MemberCapability, :capability_id, id, mine, theirs, [])

      %{group: :courses, id: id} ->
        move_record(MemberCourse, :course_id, id, mine, theirs, [:evidence_key])

      %{group: :certifications, id: id} ->
        move_record(MemberCertification, :certification_id, id, mine, theirs, [
          :task_book_key,
          :certificate_key
        ])

      _profile_item ->
        []
    end)
  end

  defp move_record(schema, catalog_field, catalog_id, mine, theirs, key_fields) do
    replaced =
      Repo.all(
        from r in schema,
          where: r.member_id == ^mine.id and field(r, ^catalog_field) == ^catalog_id
      )

    Enum.each(replaced, &Repo.delete!/1)

    Repo.update_all(
      from(r in schema,
        where: r.member_id == ^theirs.id and field(r, ^catalog_field) == ^catalog_id
      ),
      set: [member_id: mine.id]
    )

    for record <- replaced, field <- key_fields, key = Map.get(record, field), do: key
  end

  defp move_activity(mine, theirs) do
    # One row per operation and member: where both profiles have one, the
    # survivor's stands and the other stays behind on the retired profile.
    for schema <- [OperationAttendance, OperationRsvp] do
      taken = from r in schema, where: r.member_id == ^mine.id, select: r.operation_id

      Repo.update_all(
        from(r in schema,
          where: r.member_id == ^theirs.id and r.operation_id not in subquery(taken)
        ),
        set: [member_id: mine.id]
      )
    end

    for {schema, field} <- [
          {Sighting, :member_id},
          {NetCheckin, :member_id},
          {NetSession, :started_by_member_id},
          {NetSession, :net_control_member_id}
        ] do
      Repo.update_all(
        from(r in schema, where: field(r, ^field) == ^theirs.id),
        set: [{field, mine.id}]
      )
    end

    :ok
  end

  defp inherit_standing(%{gains: %{approved?: true}} = plan, mine, survivor) do
    from_status = to_string(mine.status)

    with {:ok, mine} <- mine |> Member.status_changeset(:approved) |> Repo.update(),
         {:ok, _audit} <-
           audit(mine, survivor, from_status, "approved", "Merged with #{plan.other.email}") do
      {:ok, mine}
    end
  end

  defp inherit_standing(_plan, mine, _survivor), do: {:ok, mine}

  defp retire_member(%{other_member: %Member{status: :inactive} = theirs}, _survivor) do
    {:ok, theirs}
  end

  defp retire_member(%{other_member: theirs}, survivor) do
    from_status = to_string(theirs.status)

    with {:ok, _audit} <-
           audit(theirs, survivor, from_status, "inactive", "Merged into #{survivor.email}") do
      theirs |> Member.status_changeset(:inactive) |> Repo.update()
    end
  end

  # Only approved members hold positions, so they follow the person when the
  # surviving profile is approved and are vacated otherwise.
  defp move_or_vacate_positions(%Member{status: :approved} = mine, theirs) do
    Repo.update_all(
      from(mp in MemberPosition, where: mp.member_id == ^theirs.id),
      set: [member_id: mine.id]
    )
  end

  defp move_or_vacate_positions(_mine, theirs) do
    Repo.delete_all(from mp in MemberPosition, where: mp.member_id == ^theirs.id)
  end

  defp audit(member, actor, from_status, to_status, reason) do
    %MembershipAudit{}
    |> MembershipAudit.changeset(%{
      member_id: member.id,
      actor_user_id: actor.id,
      from_status: from_status,
      to_status: to_status,
      reason: reason
    })
    |> Repo.insert()
  end

  ## Accounts

  defp absorb_account(survivor, other) do
    for {schema, field} <- [
          {MembershipAudit, :actor_user_id},
          {Operation, :created_by_id},
          {OperationAttachment, :uploaded_by_id},
          {UserEmail, :user_id}
        ] do
      Repo.update_all(
        from(r in schema, where: field(r, ^field) == ^other.id),
        set: [{field, survivor.id}]
      )
    end

    expired_tokens = Repo.all_by(UserToken, user_id: other.id)

    for schema <- [UserToken, RecoveryCode, OAuth.Token, OAuth.AuthorizationCode] do
      Repo.delete_all(from r in schema, where: r.user_id == ^other.id)
    end

    with {:ok, _other} <- other |> User.deactivate_changeset(survivor) |> Repo.update(),
         {:ok, _email} <-
           %UserEmail{user_id: survivor.id}
           |> UserEmail.changeset(%{email: other.email})
           |> Repo.insert() do
      {:ok, expired_tokens}
    end
  end

  defp inherit_admin(%User{is_admin: false} = survivor, %User{is_admin: true}) do
    Accounts.promote_to_admin(survivor)
  end

  defp inherit_admin(survivor, _other), do: {:ok, survivor}

  ## Plan

  defp gains(survivor, survivor_member, other, other_member) do
    approved? =
      match?(%Member{status: :approved}, other_member) and
        match?(%Member{}, survivor_member) and survivor_member.status != :approved

    ends_approved? = approved? or match?(%Member{status: :approved}, survivor_member)

    %{
      approved?: approved?,
      positions: if(ends_approved?, do: positions(other_member), else: []),
      admin?: other.is_admin and not survivor.is_admin
    }
  end

  defp positions(nil), do: []

  defp positions(%Member{id: member_id}) do
    Repo.all(
      from p in Position,
        join: mp in MemberPosition,
        on: mp.position_id == p.id,
        where: mp.member_id == ^member_id,
        order_by: p.sort_order
    )
  end

  # Nothing to choose unless both accounts have a profile: with one profile
  # between them it is kept (or adopted) as it is.
  defp items(%Member{} = mine, %Member{} = theirs) do
    profile_items(mine, theirs) ++
      capability_items(mine, theirs) ++
      course_items(mine, theirs) ++
      certification_items(mine, theirs)
  end

  defp items(_mine, _theirs), do: []

  defp profile_items(mine, theirs) do
    for {key, label, fields} <- @profile_fields,
        their_value = describe_fields(theirs, fields),
        Map.take(mine, fields) != Map.take(theirs, fields) do
      my_value = describe_fields(mine, fields)

      %{
        key: key,
        group: :profile,
        label: label,
        mine: my_value,
        theirs: their_value,
        default: is_nil(my_value)
      }
    end
  end

  defp describe_fields(member, [:qth_address, :qth_point]) do
    case {member.qth_address, member.qth_point} do
      {nil, nil} -> nil
      {nil, _point} -> "Map pin only"
      {address, nil} -> address
      {address, _point} -> "#{address} (with map pin)"
    end
  end

  defp describe_fields(member, @emergency_contact_fields) do
    case member do
      %{emergency_contact_name: nil} ->
        nil

      %{emergency_contact_relation: nil} = m ->
        "#{m.emergency_contact_name}, #{m.emergency_contact_phone}"

      m ->
        "#{m.emergency_contact_name} (#{m.emergency_contact_relation}), #{m.emergency_contact_phone}"
    end
  end

  defp describe_fields(member, [:license_class]) do
    if member.license_class do
      member.license_class |> to_string() |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp describe_fields(member, [field]), do: Map.get(member, field)

  # A capability is a plain claim, so one both profiles make is already the
  # survivor's and is not offered.
  defp capability_items(mine, theirs) do
    claimed = from c in MemberCapability, where: c.member_id == ^mine.id, select: c.capability_id

    records =
      Repo.all(
        from c in MemberCapability,
          join: capability in assoc(c, :capability),
          where: c.member_id == ^theirs.id and c.capability_id not in subquery(claimed),
          order_by: capability.name,
          preload: [capability: capability]
      )

    for record <- records do
      %{
        key: "capability:#{record.capability_id}",
        group: :capabilities,
        id: record.capability_id,
        label: record.capability.name,
        mine: nil,
        theirs: "Claimed",
        default: true
      }
    end
  end

  defp course_items(mine, theirs) do
    own = Map.new(Repo.all_by(MemberCourse, member_id: mine.id), &{&1.course_id, &1})

    records =
      Repo.all(
        from c in MemberCourse,
          join: course in assoc(c, :course),
          where: c.member_id == ^theirs.id,
          order_by: course.name,
          preload: [course: course]
      )

    for record <- records do
      mine = own[record.course_id]

      %{
        key: "course:#{record.course_id}",
        group: :courses,
        id: record.course_id,
        label: record.course.name,
        mine: mine && describe_course(mine),
        theirs: describe_course(record),
        default: is_nil(mine)
      }
    end
  end

  defp certification_items(mine, theirs) do
    own =
      Map.new(Repo.all_by(MemberCertification, member_id: mine.id), &{&1.certification_id, &1})

    records =
      Repo.all(
        from c in MemberCertification,
          join: certification in assoc(c, :certification),
          where: c.member_id == ^theirs.id,
          order_by: certification.name,
          preload: [certification: certification]
      )

    for record <- records do
      mine = own[record.certification_id]

      %{
        key: "certification:#{record.certification_id}",
        group: :certifications,
        id: record.certification_id,
        label: record.certification.name,
        mine: mine && describe_certification(mine),
        theirs: describe_certification(record),
        default: is_nil(mine)
      }
    end
  end

  defp describe_course(record) do
    describe_record([
      dated("Completed", record.completed_on),
      record.evidence_filename && "evidence #{record.evidence_filename}",
      record.verified && "verified"
    ])
  end

  defp describe_certification(record) do
    describe_record([
      dated("Issued", record.issued_on),
      record.task_book_filename && "task book #{record.task_book_filename}",
      record.certificate_filename && "certificate #{record.certificate_filename}",
      record.verified && "verified"
    ])
  end

  defp dated(_verb, nil), do: nil
  defp dated(verb, %Date{} = date), do: "#{verb} #{Date.to_iso8601(date)}"

  defp describe_record(parts) do
    case Enum.filter(parts, & &1) do
      [] -> "On record"
      parts -> Enum.join(parts, ", ")
    end
  end
end

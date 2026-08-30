defmodule McEmcomm.Members.MembershipAudit do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :id, autogenerate: true}
  schema "membership_audit" do
    field :from_status, :string
    field :to_status, :string
    field :reason, :string
    field :inserted_at, :utc_datetime_usec

    belongs_to :member, McEmcomm.Members.Member
    belongs_to :actor_user, McEmcomm.Accounts.User
  end

  @required_reason_statuses ~w(rejected inactive)

  @doc false
  def changeset(audit, attrs) do
    audit
    |> cast(attrs, [:member_id, :actor_user_id, :from_status, :to_status, :reason])
    |> validate_required([:member_id, :actor_user_id, :from_status, :to_status])
    |> put_change(:inserted_at, DateTime.utc_now())
    |> validate_reason_required()
  end

  defp validate_reason_required(changeset) do
    to_status = get_field(changeset, :to_status)

    if to_status in @required_reason_statuses do
      validate_required(changeset, [:reason])
    else
      changeset
    end
  end
end

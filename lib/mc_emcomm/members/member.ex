defmodule McEmcomm.Members.Member do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @quadrants ~w(NE NW SE SW out_of_county)a
  @license_classes ~w(technician general amateur_extra advanced novice)a
  @roles ~w(president vice_president secretary treasurer emergency_coordinator
            assistant_emergency_coordinator director_at_large member)a
  @statuses ~w(pending approved rejected inactive)a

  def quadrants, do: @quadrants
  def license_classes, do: @license_classes
  def roles, do: @roles
  def statuses, do: @statuses

  schema "members" do
    field :call_sign, :string
    field :name, :string
    field :qth_address, :string
    field :qth_point, Geo.PostGIS.Geometry
    field :quadrant, Ecto.Enum, values: @quadrants
    field :license_class, Ecto.Enum, values: @license_classes
    field :role, Ecto.Enum, values: @roles, default: :member
    field :status, Ecto.Enum, values: @statuses, default: :pending

    belongs_to :user, McEmcomm.Accounts.User
    has_many :started_net_sessions, McEmcomm.Net.NetSession, foreign_key: :started_by_member_id

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the fields a member may edit on their own profile."
  def profile_changeset(member, attrs) do
    member
    |> cast(attrs, [
      :call_sign,
      :name,
      :qth_address,
      :qth_point,
      :quadrant,
      :license_class
    ])
    |> validate_required([:name])
    |> validate_call_sign()
  end

  @doc "Changeset for admin-only fields (role)."
  def role_changeset(member, attrs) do
    member
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end

  @doc "Changeset used when creating a member record on registration."
  def registration_changeset(member, attrs) do
    member
    |> cast(attrs, [:user_id, :name, :call_sign])
    |> validate_required([:user_id, :name])
    |> validate_call_sign()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  @doc false
  def status_changeset(member, to_status) do
    change(member, status: to_status)
  end

  defp validate_call_sign(changeset) do
    changeset
    |> update_change(:call_sign, fn
      nil -> nil
      call_sign -> call_sign |> String.trim() |> String.upcase()
    end)
    |> validate_length(:call_sign, max: 16)
    |> unique_constraint(:call_sign, name: :members_call_sign_index)
  end
end

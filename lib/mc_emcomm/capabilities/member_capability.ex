defmodule McEmcomm.Capabilities.MemberCapability do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "member_capabilities" do
    field :notes, :string

    belongs_to :member, McEmcomm.Members.Member
    belongs_to :capability, McEmcomm.Capabilities.Capability

    timestamps(type: :utc_datetime)
  end

  def changeset(member_capability, attrs) do
    member_capability
    |> cast(attrs, [:member_id, :capability_id, :notes])
    |> validate_required([:member_id, :capability_id])
    |> foreign_key_constraint(:member_id)
    |> foreign_key_constraint(:capability_id)
    |> unique_constraint([:member_id, :capability_id])
  end
end

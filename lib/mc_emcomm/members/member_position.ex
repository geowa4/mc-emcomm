defmodule McEmcomm.Members.MemberPosition do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "member_positions" do
    belongs_to :member, McEmcomm.Members.Member
    belongs_to :position, McEmcomm.Members.Position

    timestamps(type: :utc_datetime)
  end
end

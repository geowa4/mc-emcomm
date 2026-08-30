defmodule McEmcomm.Members.Position do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "positions" do
    field :name, :string
    field :sort_order, :integer

    many_to_many :members, McEmcomm.Members.Member, join_through: McEmcomm.Members.MemberPosition

    timestamps(type: :utc_datetime)
  end
end

defmodule McEmcomm.Members.Position do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "positions" do
    field :name, :string
    field :sort_order, :integer

    many_to_many :members, McEmcomm.Members.Member, join_through: McEmcomm.Members.MemberPosition

    timestamps(type: :utc_datetime)
  end

  def changeset(position, attrs) do
    position
    |> cast(attrs, [:name, :sort_order])
    |> validate_required([:name, :sort_order])
    |> validate_number(:sort_order, greater_than: 0)
    |> unique_constraint(:name)
    |> unique_constraint(:sort_order)
  end
end

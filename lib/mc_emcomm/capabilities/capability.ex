defmodule McEmcomm.Capabilities.Capability do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "capabilities" do
    field :name, :string
    field :code, :string
    field :description, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(capability, attrs) do
    capability
    |> cast(attrs, [:name, :code, :description, :active])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end

defmodule McEmcomm.Locations.DefaultLocation do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "default_locations" do
    field :name, :string
    field :point, Geo.PostGIS.Geometry
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(default_location, attrs) do
    default_location
    |> cast(attrs, [:name, :point, :position])
    |> validate_required([:name, :point])
    |> unique_constraint(:name)
  end
end

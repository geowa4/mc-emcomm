defmodule McEmcomm.Operations.OperationLocation do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "operation_locations" do
    field :name, :string
    field :point, Geo.PostGIS.Geometry
    field :geofence_radius_m, :integer, default: 500
    field :notes, :string
    field :position, :integer, default: 0

    belongs_to :operation, McEmcomm.Operations.Operation

    timestamps(type: :utc_datetime)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:operation_id, :name, :point, :geofence_radius_m, :notes, :position])
    |> validate_required([:operation_id, :name, :point])
    |> validate_number(:geofence_radius_m, greater_than: 0)
    |> foreign_key_constraint(:operation_id)
    |> unique_constraint([:operation_id, :name])
  end
end

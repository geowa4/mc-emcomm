defmodule McEmcomm.Operations.OperationAttendance do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @sources ~w(manual asset_checkin admin)a
  def sources, do: @sources

  schema "operation_attendance" do
    field :source, Ecto.Enum, values: @sources
    field :recorded_at, :utc_datetime_usec

    belongs_to :operation, McEmcomm.Operations.Operation
    belongs_to :member, McEmcomm.Members.Member
    belongs_to :sighting, McEmcomm.Sightings.Sighting

    timestamps(type: :utc_datetime)
  end

  def changeset(attendance, attrs) do
    attendance
    |> cast(attrs, [:operation_id, :member_id, :source, :sighting_id, :recorded_at])
    |> validate_required([:operation_id, :member_id, :source, :recorded_at])
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:member_id)
    |> foreign_key_constraint(:sighting_id)
    |> unique_constraint([:operation_id, :member_id])
  end
end

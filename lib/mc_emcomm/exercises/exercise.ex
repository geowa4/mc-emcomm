defmodule McEmcomm.Exercises.Exercise do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @visibilities ~w(public members)a
  def visibilities, do: @visibilities

  schema "exercises" do
    field :title, :string
    field :description, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :visibility, Ecto.Enum, values: @visibilities, default: :members

    belongs_to :created_by, McEmcomm.Accounts.User

    has_many :locations, McEmcomm.Exercises.ExerciseLocation, preload_order: [asc: :position]
    has_many :attachments, McEmcomm.Exercises.ExerciseAttachment
    has_many :attendance, McEmcomm.Exercises.ExerciseAttendance

    timestamps(type: :utc_datetime)
  end

  def changeset(exercise, attrs) do
    exercise
    |> cast(attrs, [:title, :description, :starts_at, :ends_at, :visibility, :created_by_id])
    |> validate_required([:title, :starts_at, :ends_at, :created_by_id])
    |> validate_ends_after_starts()
    |> foreign_key_constraint(:created_by_id)
  end

  defp validate_ends_after_starts(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
      add_error(changeset, :ends_at, "must be after the start time")
    else
      changeset
    end
  end
end

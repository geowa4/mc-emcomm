defmodule McEmcomm.Exercises.ExerciseAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "exercise_attachments" do
    field :key, :string
    field :filename, :string
    field :content_type, :string
    field :description, :string

    belongs_to :exercise, McEmcomm.Exercises.Exercise
    belongs_to :uploaded_by, McEmcomm.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:exercise_id, :key, :filename, :content_type, :description, :uploaded_by_id])
    |> validate_required([
      :exercise_id,
      :key,
      :filename,
      :content_type,
      :description,
      :uploaded_by_id
    ])
    |> validate_length(:description, min: 1)
    |> foreign_key_constraint(:exercise_id)
    |> foreign_key_constraint(:uploaded_by_id)
  end
end

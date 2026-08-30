defmodule McEmcomm.Certifications.Certification do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "certifications" do
    field :name, :string
    field :code, :string
    field :description, :string
    field :requires_task_book, :boolean, default: true
    field :active, :boolean, default: true

    belongs_to :prerequisite_course, McEmcomm.Courses.Course

    timestamps(type: :utc_datetime)
  end

  def changeset(certification, attrs) do
    certification
    |> cast(attrs, [
      :name,
      :code,
      :description,
      :prerequisite_course_id,
      :requires_task_book,
      :active
    ])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> foreign_key_constraint(:prerequisite_course_id)
  end
end

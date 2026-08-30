defmodule McEmcomm.Courses.MemberCourse do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "member_courses" do
    field :completed_on, :date
    field :evidence_key, :string
    field :evidence_filename, :string
    field :evidence_content_type, :string
    field :verified, :boolean, default: false

    belongs_to :member, McEmcomm.Members.Member
    belongs_to :course, McEmcomm.Courses.Course

    timestamps(type: :utc_datetime)
  end

  @doc "Fields a member may set on their own record."
  def member_changeset(member_course, attrs) do
    member_course
    |> cast(attrs, [
      :member_id,
      :course_id,
      :completed_on,
      :evidence_key,
      :evidence_filename,
      :evidence_content_type
    ])
    |> validate_required([:member_id, :course_id])
    |> foreign_key_constraint(:member_id)
    |> foreign_key_constraint(:course_id)
    |> unique_constraint([:member_id, :course_id])
  end

  @doc "Admin-only verification flag."
  def verify_changeset(member_course, attrs) do
    cast(member_course, attrs, [:verified])
  end
end

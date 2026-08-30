defmodule McEmcomm.Certifications.MemberCertification do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "member_certifications" do
    field :issued_on, :date
    field :expires_on, :date
    field :task_book_key, :string
    field :task_book_filename, :string
    field :task_book_content_type, :string
    field :certificate_key, :string
    field :certificate_filename, :string
    field :certificate_content_type, :string
    field :verified, :boolean, default: false
    field :notes, :string

    belongs_to :member, McEmcomm.Members.Member
    belongs_to :certification, McEmcomm.Certifications.Certification

    timestamps(type: :utc_datetime)
  end

  @doc "Fields a member may set on their own record (both upload slots + notes)."
  def member_changeset(member_certification, attrs) do
    member_certification
    |> cast(attrs, [
      :member_id,
      :certification_id,
      :issued_on,
      :expires_on,
      :task_book_key,
      :task_book_filename,
      :task_book_content_type,
      :certificate_key,
      :certificate_filename,
      :certificate_content_type,
      :notes
    ])
    |> validate_required([:member_id, :certification_id])
    |> foreign_key_constraint(:member_id)
    |> foreign_key_constraint(:certification_id)
    |> unique_constraint([:member_id, :certification_id])
  end

  @doc "Admin-only verification flag."
  def verify_changeset(member_certification, attrs) do
    cast(member_certification, attrs, [:verified])
  end
end

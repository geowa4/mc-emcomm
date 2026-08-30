defmodule McEmcomm.Repo.Migrations.CreateMemberCourses do
  use Ecto.Migration

  def change do
    create table(:member_courses) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :course_id, references(:courses, on_delete: :delete_all), null: false
      add :completed_on, :date
      add :evidence_key, :string
      add :evidence_filename, :string
      add :evidence_content_type, :string
      add :verified, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:member_courses, [:member_id, :course_id])
  end
end

defmodule McEmcomm.Repo.Migrations.CreateCertifications do
  use Ecto.Migration

  def change do
    create table(:certifications) do
      add :name, :citext, null: false
      add :code, :string
      add :description, :text
      add :prerequisite_course_id, references(:courses, on_delete: :nilify_all)
      add :requires_task_book, :boolean, null: false, default: true
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:certifications, [:name])
    create index(:certifications, [:prerequisite_course_id])
  end
end

defmodule McEmcomm.Repo.Migrations.CreateExerciseAttachments do
  use Ecto.Migration

  def change do
    create table(:exercise_attachments) do
      add :exercise_id, references(:exercises, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :description, :text, null: false
      add :uploaded_by_id, references(:users, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:exercise_attachments, [:exercise_id])

    create constraint(:exercise_attachments, :description_not_empty,
             check: "length(btrim(description)) > 0"
           )
  end
end

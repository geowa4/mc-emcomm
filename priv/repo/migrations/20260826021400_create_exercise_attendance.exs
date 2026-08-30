defmodule McEmcomm.Repo.Migrations.CreateExerciseAttendance do
  use Ecto.Migration

  def change do
    create table(:exercise_attendance) do
      add :exercise_id, references(:exercises, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :sighting_id, references(:sightings, on_delete: :nilify_all)
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:exercise_attendance, [:exercise_id, :member_id])
  end
end

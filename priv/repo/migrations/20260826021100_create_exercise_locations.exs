defmodule McEmcomm.Repo.Migrations.CreateExerciseLocations do
  use Ecto.Migration

  def change do
    create table(:exercise_locations) do
      add :exercise_id, references(:exercises, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :point, :"geography(Point,4326)", null: false
      add :geofence_radius_m, :integer, null: false, default: 500
      add :notes, :text
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:exercise_locations, [:exercise_id])
    create index(:exercise_locations, [:point], using: :gist)
    create unique_index(:exercise_locations, [:exercise_id, :name])
  end
end

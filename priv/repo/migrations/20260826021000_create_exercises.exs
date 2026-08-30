defmodule McEmcomm.Repo.Migrations.CreateExercises do
  use Ecto.Migration

  def change do
    create table(:exercises) do
      add :title, :string, null: false
      add :description, :text
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :visibility, :string, null: false, default: "members"
      add :created_by_id, references(:users, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:exercises, :ends_at_after_starts_at, check: "ends_at > starts_at")
    create index(:exercises, [:starts_at])
    create index(:exercises, [:visibility])
  end
end

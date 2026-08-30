defmodule McEmcomm.Repo.Migrations.CreateNetSessions do
  use Ecto.Migration

  def change do
    create table(:net_sessions) do
      add :started_by_member_id, references(:members, on_delete: :nothing), null: false
      add :name, :string
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:net_sessions, [:started_at])
  end
end

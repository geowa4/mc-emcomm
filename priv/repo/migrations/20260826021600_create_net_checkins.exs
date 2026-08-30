defmodule McEmcomm.Repo.Migrations.CreateNetCheckins do
  use Ecto.Migration

  def change do
    create table(:net_checkins) do
      add :net_session_id, references(:net_sessions, on_delete: :delete_all), null: false
      add :call_sign, :citext, null: false
      add :member_id, references(:members, on_delete: :nilify_all)
      add :quadrant, :string
      add :notes, :text
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:net_checkins, [:net_session_id])
    create index(:net_checkins, [:member_id])
  end
end

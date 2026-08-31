defmodule McEmcomm.Repo.Migrations.AddEndedAtToNetCheckins do
  use Ecto.Migration

  # Additive-only (expand step): old code ignores the new nullable column.
  def change do
    alter table(:net_checkins) do
      add :ended_at, :utc_datetime_usec
    end
  end
end

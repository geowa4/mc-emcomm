defmodule McEmcomm.Repo.Migrations.AddNotifyOnNewMemberToPositions do
  use Ecto.Migration

  # Expand step for "email these position holders when a new member
  # confirms". Adding a NOT NULL column with a constant default is a
  # catalog-only change on Postgres 11+ (no table rewrite), and `positions`
  # holds a handful of rows, so the brief ACCESS EXCLUSIVE lock is harmless
  # (see CONTRIBUTING.md § Database & migrations). Old code never selects the
  # column, so it keeps working during the blue-green rollout. There is no
  # contract step for this feature.

  def change do
    alter table(:positions) do
      add :notify_on_new_member, :boolean, default: false, null: false
    end
  end
end

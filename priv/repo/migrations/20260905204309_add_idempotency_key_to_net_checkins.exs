defmodule McEmcomm.Repo.Migrations.AddIdempotencyKeyToNetCheckins do
  use Ecto.Migration

  # Expand step for idempotent MCP check-ins (SPEC.md §7.17, §28). The
  # nullable column is a catalog-only change; the partial unique index is
  # built concurrently because `net_checkins` is a live table, which is why
  # the migration runs outside a transaction and without the migration lock
  # (CONTRIBUTING.md § Database & migrations). Old code never reads the
  # column, so it keeps working during the blue-green rollout. There is no
  # contract step for this feature.

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    alter table(:net_checkins) do
      add :idempotency_key, :string
    end

    create unique_index(:net_checkins, [:net_session_id, :idempotency_key],
             name: :net_checkins_idempotency_key_index,
             where: "idempotency_key IS NOT NULL",
             concurrently: true
           )
  end
end

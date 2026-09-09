defmodule McEmcomm.Repo.Migrations.CreateOperationRsvps do
  use Ecto.Migration

  # Expand step for operation RSVPs (SPEC.md §7.28, §9.12). RSVPs are a
  # member's intent to attend, kept apart from `operation_attendance`, which
  # records who actually showed up. The table is brand new, so nothing reads
  # it during the blue-green rollout and its indexes can be built inside the
  # transaction (CONTRIBUTING.md § Database & migrations). There is no
  # contract step for this feature.

  def change do
    create table(:operation_rsvps) do
      add :operation_id, references(:operations, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :response, :string, null: false
      add :note, :string
      add :responded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:operation_rsvps, [:operation_id, :member_id])
    create index(:operation_rsvps, [:member_id])
  end
end

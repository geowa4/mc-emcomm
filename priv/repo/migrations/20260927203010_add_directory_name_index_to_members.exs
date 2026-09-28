defmodule McEmcomm.Repo.Migrations.AddDirectoryNameIndexToMembers do
  use Ecto.Migration

  # Expand step for the member directory (SPEC.md §7.2, §30), which lists
  # approved members ordered by name. `members` is a live table, so the index
  # is built concurrently, outside a transaction and without the migration
  # lock (CONTRIBUTING.md § Database & migrations). Old code never depends on
  # the index, so it keeps working during the blue-green rollout. There is no
  # contract step for this feature.

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:members, [:name, :id],
             name: :members_directory_name_index,
             where: "status = 'approved'",
             concurrently: true
           )
  end
end

defmodule McEmcomm.Repo.Migrations.AddGrantsAdminToPositions do
  use Ecto.Migration

  def change do
    alter table(:positions) do
      add :grants_admin, :boolean, default: false, null: false
    end
  end
end

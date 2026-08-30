defmodule McEmcomm.Repo.Migrations.CreateMemberCapabilities do
  use Ecto.Migration

  def change do
    create table(:member_capabilities) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :capability_id, references(:capabilities, on_delete: :delete_all), null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:member_capabilities, [:member_id, :capability_id])
  end
end

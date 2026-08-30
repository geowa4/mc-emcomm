defmodule McEmcomm.Repo.Migrations.CreateCapabilities do
  use Ecto.Migration

  def change do
    create table(:capabilities) do
      add :name, :citext, null: false
      add :code, :string
      add :description, :text
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:capabilities, [:name])
  end
end

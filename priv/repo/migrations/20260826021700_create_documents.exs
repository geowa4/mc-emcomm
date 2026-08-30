defmodule McEmcomm.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :title, :string, null: false
      add :key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :members_only, :boolean, null: false, default: true
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end
  end
end

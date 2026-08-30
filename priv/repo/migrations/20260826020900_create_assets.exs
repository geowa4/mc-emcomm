defmodule McEmcomm.Repo.Migrations.CreateAssets do
  use Ecto.Migration

  def change do
    create table(:assets) do
      add :public_id, :char, size: 6, null: false
      add :name, :string, null: false
      add :description, :text
      add :image_key, :string
      add :image_filename, :string
      add :image_content_type, :string
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assets, [:public_id])
  end
end

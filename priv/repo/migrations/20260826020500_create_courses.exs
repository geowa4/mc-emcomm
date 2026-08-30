defmodule McEmcomm.Repo.Migrations.CreateCourses do
  use Ecto.Migration

  def change do
    create table(:courses) do
      add :name, :citext, null: false
      add :code, :string
      add :description, :text
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:courses, [:name])
  end
end

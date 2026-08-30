defmodule McEmcomm.Repo.Migrations.CreateMembers do
  use Ecto.Migration

  def change do
    create table(:members) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :call_sign, :citext
      add :name, :string, null: false
      add :qth_address, :text
      add :qth_point, :"geography(Point,4326)"
      add :quadrant, :string
      add :license_class, :string
      add :role, :string, null: false, default: "member"
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:members, [:user_id])

    create unique_index(:members, [:call_sign],
             name: :members_call_sign_index,
             where: "call_sign IS NOT NULL"
           )

    create index(:members, [:qth_point], using: :gist)
    create index(:members, [:status])
    create index(:members, [:role])
  end
end

defmodule McEmcomm.Repo.Migrations.CreateMembershipAudit do
  use Ecto.Migration

  def change do
    create table(:membership_audit) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :actor_user_id, references(:users, on_delete: :nothing), null: false
      add :from_status, :string, null: false
      add :to_status, :string, null: false
      add :reason, :text

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:membership_audit, [:member_id])
  end
end

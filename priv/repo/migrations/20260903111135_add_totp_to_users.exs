defmodule McEmcomm.Repo.Migrations.AddTotpToUsers do
  use Ecto.Migration

  # Expand step for optional TOTP two-factor authentication. Everything here
  # is additive: the new users columns are nullable with no default, which is
  # a catalog-only change in Postgres (no table rewrite, so no lock_timeout is
  # needed), and the recovery code table is brand new, so its index can be
  # built inside the transaction (nothing reads an empty table concurrently;
  # see CONTRIBUTING.md § Database & migrations). Old code never selects the
  # new columns, so it keeps working during the blue-green rollout. There is
  # no contract step for this feature.

  def change do
    alter table(:users) do
      add :totp_secret, :binary
      add :totp_confirmed_at, :utc_datetime
      add :totp_last_used_at, :utc_datetime
    end

    create table(:users_recovery_codes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :hashed_code, :binary, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:users_recovery_codes, [:user_id, :hashed_code])
  end
end

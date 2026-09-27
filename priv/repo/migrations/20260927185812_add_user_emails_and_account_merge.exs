defmodule McEmcomm.Repo.Migrations.AddUserEmailsAndAccountMerge do
  use Ecto.Migration

  # Expand step for additional email addresses and account merging
  # (SPEC.md §7.29, §29). `users_emails` is brand new, so nothing reads it
  # during the blue-green rollout and its indexes can be built inside the
  # transaction (CONTRIBUTING.md § Database & migrations). The two `users`
  # columns are nullable and unknown to the old code, which keeps working:
  # an account is deactivated by data the old code already honours (no
  # tokens, no password, a primary address nothing can be mailed to), not by
  # the flag alone. There is no contract step for this feature.

  def change do
    create table(:users_emails) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :email, :citext, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users_emails, [:email])
    create index(:users_emails, [:user_id])

    alter table(:users) do
      add :deactivated_at, :utc_datetime
      add :merged_into_id, references(:users, on_delete: :nilify_all)
    end
  end
end

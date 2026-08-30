defmodule MyApp.Repo.Migrations.CreateWebhookEvents do
  use Ecto.Migration

  def change do
    create table(:webhook_events) do
      add :svix_id, :string, null: false
      add :event_type, :string
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:webhook_events, [:svix_id])
  end
end

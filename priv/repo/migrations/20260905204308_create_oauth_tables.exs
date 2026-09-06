defmodule McEmcomm.Repo.Migrations.CreateOauthTables do
  use Ecto.Migration

  # Expand step for the MCP connector's OAuth 2.1 authorization server
  # (SPEC.md §28, §7.25–§7.27). All three tables are brand new, so nothing
  # reads them during the blue-green rollout and their indexes can be built
  # inside the transaction (CONTRIBUTING.md § Database & migrations). Secrets
  # never land here in the clear: client secrets, authorization codes, and
  # tokens are stored as SHA-256 digests only. `client_id` is a string rather
  # than a foreign key because the optional static client configured from the
  # environment has no row. There is no contract step for this feature.

  def change do
    create table(:oauth_clients) do
      add :client_id, :string, null: false
      add :hashed_secret, :binary
      add :client_name, :string
      add :redirect_uris, {:array, :string}, null: false, default: []
      add :token_endpoint_auth_method, :string, null: false
      add :grant_types, {:array, :string}, null: false, default: []
      add :response_types, {:array, :string}, null: false, default: []
      add :application_type, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_clients, [:client_id])

    create table(:oauth_authorization_codes) do
      add :hashed_code, :binary, null: false
      add :client_id, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :redirect_uri, :string, null: false
      add :code_challenge, :string, null: false
      add :resource, :string, null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:oauth_authorization_codes, [:hashed_code])
    create index(:oauth_authorization_codes, [:user_id])

    create table(:oauth_tokens) do
      add :hashed_token, :binary, null: false
      add :kind, :string, null: false
      add :client_id, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :audience, :string, null: false
      add :family_id, :uuid, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:oauth_tokens, [:hashed_token])
    create index(:oauth_tokens, [:family_id])
    create index(:oauth_tokens, [:user_id])
  end
end

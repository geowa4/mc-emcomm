defmodule McEmcomm.OAuth.AuthorizationCode do
  @moduledoc """
  A single-use authorization code (SPEC.md §7.26). Only the SHA-256 digest of
  the code is stored; the row binds it to the user, client, exact redirect
  URI, PKCE challenge, resource, and granted scopes it was issued for.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "oauth_authorization_codes" do
    field :hashed_code, :binary, redact: true
    field :client_id, :string
    field :redirect_uri, :string
    field :code_challenge, :string
    field :resource, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, McEmcomm.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end

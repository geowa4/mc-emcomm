defmodule McEmcomm.OAuth.Token do
  @moduledoc """
  An opaque access or refresh token (SPEC.md §7.27), stored as its SHA-256
  digest. Tokens issued together share a `family_id`; rotation revokes the
  presented refresh token, and presenting an already-rotated one revokes the
  whole family (refresh-token reuse detection, OAuth 2.1 §6.1).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @kinds ~w(access refresh)a
  def kinds, do: @kinds

  schema "oauth_tokens" do
    field :hashed_token, :binary, redact: true
    field :kind, Ecto.Enum, values: @kinds
    field :client_id, :string
    field :scopes, {:array, :string}, default: []
    field :audience, :string
    field :family_id, Ecto.UUID
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, McEmcomm.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end

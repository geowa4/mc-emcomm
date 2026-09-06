defmodule McEmcomm.OAuth.Client do
  @moduledoc """
  An OAuth client registered through `POST /oauth/register` (RFC 7591), or
  the optional static client built from configuration (which has no row and
  no `id`). The secret is stored SHA-256-hashed and redacted from inspection.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias McEmcomm.OAuth

  @type t :: %__MODULE__{}

  @grant_types ["authorization_code", "refresh_token"]
  @response_types ["code"]
  @application_types ["web", "native"]

  schema "oauth_clients" do
    field :client_id, :string
    field :hashed_secret, :binary, redact: true
    field :client_name, :string
    field :redirect_uris, {:array, :string}, default: []
    field :token_endpoint_auth_method, :string
    field :grant_types, {:array, :string}, default: @grant_types
    field :response_types, {:array, :string}, default: @response_types
    field :application_type, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates an RFC 7591 registration request. `client_id` and the hashed
  secret are set programmatically by `McEmcomm.OAuth.Clients.register/1`,
  never cast.
  """
  def registration_changeset(client, attrs) do
    client
    |> cast(attrs, [
      :client_name,
      :redirect_uris,
      :token_endpoint_auth_method,
      :grant_types,
      :response_types,
      :application_type
    ])
    |> validate_required([:redirect_uris])
    |> validate_length(:client_name, max: 160)
    |> validate_length(:redirect_uris, min: 1, max: 10)
    |> validate_redirect_uris()
    |> validate_inclusion(:token_endpoint_auth_method, OAuth.token_endpoint_auth_methods())
    |> validate_subset(:grant_types, @grant_types)
    |> validate_subset(:response_types, @response_types)
    |> validate_inclusion(:application_type, @application_types)
    |> unique_constraint(:client_id)
  end

  # Checked on the field, not the change: the schema default is `[]`, so an
  # omitted list would otherwise slip past `validate_change/3`.
  defp validate_redirect_uris(changeset) do
    case get_field(changeset, :redirect_uris) do
      uris when uris in [nil, []] ->
        add_error(changeset, :redirect_uris, "can't be blank")

      uris ->
        case Enum.reject(uris, &OAuth.allowed_redirect_uri?/1) do
          [] ->
            changeset

          rejected ->
            add_error(changeset, :redirect_uris, "not allowed: #{Enum.join(rejected, ", ")}")
        end
    end
  end

  @doc "Whether the client authenticates with a secret (as opposed to `none`)."
  @spec confidential?(t()) :: boolean()
  def confidential?(%__MODULE__{token_endpoint_auth_method: "none"}), do: false
  def confidential?(%__MODULE__{}), do: true
end

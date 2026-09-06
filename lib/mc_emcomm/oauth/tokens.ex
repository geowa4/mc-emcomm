defmodule McEmcomm.OAuth.Tokens do
  @moduledoc """
  Issues, verifies, refreshes, and revokes the connector's opaque tokens.

    * Access tokens live `MC_EMCOMM_MCP_ACCESS_TOKEN_TTL` seconds and carry
      the audience (`aud`) they were issued for; `/mcp` accepts one only when
      that audience equals `MC_EMCOMM_MCP_RESOURCE_URL` exactly.
    * Refresh tokens live `MC_EMCOMM_MCP_REFRESH_TOKEN_TTL` seconds and are
      rotated on every use; reuse of a rotated token revokes its family.
    * Raw values are returned to the caller once and never stored or logged.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.Accounts.User
  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.OAuth.Token
  alias McEmcomm.Repo

  @type issued :: %{
          access_token: String.t(),
          refresh_token: String.t(),
          token_type: String.t(),
          expires_in: pos_integer(),
          scope: String.t()
        }

  @doc """
  Issues an access/refresh pair for `user` and `client_id`, bound to
  `audience`, in a new family (or the given one when rotating).
  """
  @spec issue(User.t(), String.t(), [String.t()], String.t(), Ecto.UUID.t() | nil) ::
          {:ok, issued()}
  def issue(%User{id: user_id}, client_id, scopes, audience, family_id \\ nil) do
    family_id = family_id || Ecto.UUID.generate()
    now = DateTime.utc_now(:second)
    access = OAuth.random_secret()
    refresh = OAuth.random_secret()

    Repo.transaction(fn ->
      Repo.insert!(%Token{
        hashed_token: OAuth.hash(access),
        kind: :access,
        client_id: client_id,
        user_id: user_id,
        scopes: scopes,
        audience: audience,
        family_id: family_id,
        expires_at: DateTime.add(now, OAuth.access_token_ttl(), :second)
      })

      Repo.insert!(%Token{
        hashed_token: OAuth.hash(refresh),
        kind: :refresh,
        client_id: client_id,
        user_id: user_id,
        scopes: scopes,
        audience: audience,
        family_id: family_id,
        expires_at: DateTime.add(now, OAuth.refresh_token_ttl(), :second)
      })
    end)
    |> case do
      {:ok, _} ->
        {:ok,
         %{
           access_token: access,
           refresh_token: refresh,
           token_type: "Bearer",
           expires_in: OAuth.access_token_ttl(),
           scope: Scopes.join(scopes)
         }}
    end
  end

  @doc """
  Resolves a bearer token presented to `/mcp`: it must be a live, unexpired
  access token whose audience equals `audience` byte for byte. Returns the
  token with its user preloaded.
  """
  @spec verify_access(term(), String.t()) :: {:ok, Token.t()} | {:error, :invalid_token}
  def verify_access(raw, audience) when is_binary(raw) and raw != "" do
    now = DateTime.utc_now(:second)

    case Repo.get_by(Token, hashed_token: OAuth.hash(raw)) do
      %Token{kind: :access, revoked_at: nil, audience: ^audience, expires_at: expires_at} = token
      when is_struct(expires_at, DateTime) ->
        if DateTime.compare(expires_at, now) == :gt,
          do: {:ok, Repo.preload(token, :user)},
          else: {:error, :invalid_token}

      _ ->
        {:error, :invalid_token}
    end
  end

  def verify_access(_raw, _audience), do: {:error, :invalid_token}

  @doc """
  Rotates a refresh token: the presented token is revoked and a new pair is
  issued in the same family, with the scopes re-intersected against the
  user's *live* role. A token that was already rotated (or revoked) is
  treated as theft: the entire family is revoked and the grant fails.
  """
  @spec refresh(term(), String.t()) :: {:ok, issued()} | {:error, :invalid_grant}
  def refresh(raw, client_id) when is_binary(raw) and raw != "" do
    now = DateTime.utc_now(:second)

    case Repo.get_by(Token, hashed_token: OAuth.hash(raw)) do
      %Token{kind: :refresh, client_id: ^client_id, revoked_at: nil} = token ->
        if DateTime.compare(token.expires_at, now) == :gt,
          do: rotate(token),
          else: {:error, :invalid_grant}

      %Token{kind: :refresh, client_id: ^client_id} = reused ->
        revoke_family(reused.family_id)
        {:error, :invalid_grant}

      _ ->
        {:error, :invalid_grant}
    end
  end

  def refresh(_raw, _client_id), do: {:error, :invalid_grant}

  defp rotate(%Token{} = token) do
    token = Repo.preload(token, :user)
    scopes = Scopes.effective(token.scopes, Scope.for_user(token.user))

    if scopes == [] do
      revoke_family(token.family_id)
      {:error, :invalid_grant}
    else
      Repo.transaction(fn ->
        {1, _} =
          Token
          |> where([t], t.id == ^token.id and is_nil(t.revoked_at))
          |> Repo.update_all(set: [revoked_at: DateTime.utc_now(:second)])

        {:ok, issued} =
          issue(token.user, token.client_id, scopes, token.audience, token.family_id)

        issued
      end)
      |> case do
        {:ok, issued} -> {:ok, issued}
        {:error, _} -> {:error, :invalid_grant}
      end
    end
  end

  @doc """
  RFC 7009 revocation. A refresh token takes its whole family with it; an
  access token is revoked alone. Unknown tokens and tokens belonging to
  another client are ignored — the endpoint answers 200 either way.
  """
  @spec revoke(term(), String.t()) :: :ok
  def revoke(raw, client_id) when is_binary(raw) do
    case Repo.get_by(Token, hashed_token: OAuth.hash(raw)) do
      %Token{kind: :refresh, client_id: ^client_id} = token -> revoke_family(token.family_id)
      %Token{kind: :access, client_id: ^client_id} = token -> revoke_one(token)
      _ -> :ok
    end
  end

  def revoke(_raw, _client_id), do: :ok

  defp revoke_one(%Token{id: id}) do
    Token
    |> where([t], t.id == ^id and is_nil(t.revoked_at))
    |> Repo.update_all(set: [revoked_at: DateTime.utc_now(:second)])

    :ok
  end

  @doc "Revokes every token in a family (used on refresh-token reuse)."
  @spec revoke_family(Ecto.UUID.t()) :: :ok
  def revoke_family(family_id) do
    Token
    |> where([t], t.family_id == ^family_id and is_nil(t.revoked_at))
    |> Repo.update_all(set: [revoked_at: DateTime.utc_now(:second)])

    :ok
  end

  @doc "Deletes tokens that expired more than a day ago."
  @spec purge_expired() :: non_neg_integer()
  def purge_expired do
    cutoff = DateTime.utc_now(:second) |> DateTime.add(-1, :day)
    {count, _} = Token |> where([t], t.expires_at < ^cutoff) |> Repo.delete_all()
    count
  end
end

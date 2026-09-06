defmodule McEmcomm.OAuth.AuthorizationCodes do
  @moduledoc """
  Issues and redeems authorization codes. Every field of a code is set by
  the consent screen, never cast from a request. Redemption is a single
  `FOR UPDATE` transaction so a code can be used exactly once even under
  concurrent token requests.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Accounts.User
  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.AuthorizationCode
  alias McEmcomm.OAuth.PKCE
  alias McEmcomm.Repo

  @type grant :: %{
          client_id: String.t(),
          redirect_uri: String.t(),
          code_challenge: String.t(),
          resource: String.t(),
          scopes: [String.t()]
        }

  @doc "Mints a code for `user` bound to the approved request. Returns the raw code."
  @spec issue(User.t(), grant()) :: {:ok, String.t()}
  def issue(%User{id: user_id}, grant) do
    raw = OAuth.random_secret()

    expires_at =
      DateTime.utc_now(:second) |> DateTime.add(OAuth.auth_code_ttl(), :second)

    %AuthorizationCode{
      hashed_code: OAuth.hash(raw),
      user_id: user_id,
      client_id: grant.client_id,
      redirect_uri: grant.redirect_uri,
      code_challenge: grant.code_challenge,
      resource: grant.resource,
      scopes: grant.scopes,
      expires_at: expires_at
    }
    |> Repo.insert!()

    {:ok, raw}
  end

  @doc """
  Redeems a code once: it must exist, be unexpired and unused, belong to the
  authenticating client, match the redirect URI exactly, satisfy PKCE, and —
  when a `resource` is given — match the one it was issued for. Any failure
  is `{:error, :invalid_grant}` without saying which check failed.
  """
  @spec redeem(String.t(), map()) :: {:ok, AuthorizationCode.t()} | {:error, :invalid_grant}
  def redeem(raw_code, params) when is_binary(raw_code) do
    hashed = OAuth.hash(raw_code)

    Repo.transaction(fn ->
      code =
        AuthorizationCode
        |> where([c], c.hashed_code == ^hashed)
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %AuthorizationCode{} <- code,
           :ok <- check(code, params) do
        code
        |> Ecto.Changeset.change(used_at: DateTime.utc_now(:second))
        |> Repo.update!()
        |> Repo.preload(:user)
      else
        _ -> Repo.rollback(:invalid_grant)
      end
    end)
  end

  def redeem(_raw_code, _params), do: {:error, :invalid_grant}

  defp check(code, params) do
    now = DateTime.utc_now(:second)

    cond do
      not is_nil(code.used_at) -> :error
      DateTime.compare(code.expires_at, now) != :gt -> :error
      code.client_id != params[:client_id] -> :error
      code.redirect_uri != params[:redirect_uri] -> :error
      not PKCE.verify(params[:code_verifier], code.code_challenge) -> :error
      params[:resource] not in [nil, code.resource] -> :error
      true -> :ok
    end
  end

  @doc "Deletes codes that expired more than a day ago (housekeeping for the scrubber)."
  @spec purge_expired() :: non_neg_integer()
  def purge_expired do
    cutoff = DateTime.utc_now(:second) |> DateTime.add(-1, :day)

    {count, _} =
      AuthorizationCode
      |> where([c], c.expires_at < ^cutoff)
      |> Repo.delete_all()

    count
  end
end

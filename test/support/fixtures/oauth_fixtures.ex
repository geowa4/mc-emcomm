defmodule McEmcomm.OAuthFixtures do
  @moduledoc "Test helpers for the MCP connector's OAuth server and transport (SPEC.md §28)."

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.AuthorizationCodes
  alias McEmcomm.OAuth.Clients
  alias McEmcomm.OAuth.PKCE
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.OAuth.Tokens

  @claude_callback "https://claude.ai/api/mcp/auth_callback"
  @loopback_callback "http://127.0.0.1:6274/oauth/callback"

  def claude_callback, do: @claude_callback
  def loopback_callback, do: @loopback_callback

  @doc "A dynamically registered public client (PKCE, no secret)."
  def public_client_fixture(attrs \\ %{}) do
    {:ok, client, nil} =
      Clients.register(
        Map.merge(
          %{
            "client_name" => "Test Client",
            "redirect_uris" => [@claude_callback, "http://localhost/callback"],
            "token_endpoint_auth_method" => "none"
          },
          attrs
        )
      )

    client
  end

  @doc "A dynamically registered confidential client; returns `{client, raw_secret}`."
  def confidential_client_fixture(attrs \\ %{}) do
    {:ok, client, secret} =
      Clients.register(
        Map.merge(
          %{
            "client_name" => "Confidential Client",
            "redirect_uris" => [@claude_callback],
            "token_endpoint_auth_method" => "client_secret_post"
          },
          attrs
        )
      )

    {client, secret}
  end

  @doc "A fresh PKCE verifier and its S256 challenge."
  def pkce_fixture do
    verifier = 48 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    %{verifier: verifier, challenge: PKCE.challenge(verifier)}
  end

  @doc """
  An authorization code for `user` as the consent screen would mint it.
  Returns `{raw_code, grant}` where `grant` holds what the token request must
  repeat.
  """
  def authorization_code_fixture(user, client, opts \\ []) do
    pkce = Keyword.get_lazy(opts, :pkce, &pkce_fixture/0)

    grant = %{
      client_id: client.client_id,
      redirect_uri: Keyword.get(opts, :redirect_uri, @claude_callback),
      code_challenge: pkce.challenge,
      resource: Keyword.get(opts, :resource, OAuth.resource_url()),
      scopes: Keyword.get(opts, :scopes, Scopes.effective([], Scope.for_user(user)))
    }

    {:ok, code} = AuthorizationCodes.issue(user, grant)
    {code, Map.put(grant, :code_verifier, pkce.verifier)}
  end

  @doc "An access/refresh pair for `user`, bypassing the browser flow."
  def tokens_fixture(user, opts \\ []) do
    client_id = Keyword.get(opts, :client_id, "fixture-client")
    scopes = Keyword.get(opts, :scopes, Scopes.effective([], Scope.for_user(user)))
    audience = Keyword.get(opts, :audience, OAuth.resource_url())
    {:ok, issued} = Tokens.issue(user, client_id, scopes, audience)
    issued
  end

  @doc "Just the raw access token for `user`."
  def access_token_fixture(user, opts \\ []), do: tokens_fixture(user, opts).access_token
end

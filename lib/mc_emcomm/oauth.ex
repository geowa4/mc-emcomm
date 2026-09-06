defmodule McEmcomm.OAuth do
  @moduledoc """
  The minimal OAuth 2.1 authorization server behind the MCP connector
  (SPEC.md §28): configuration, the two discovery documents, and the
  redirect-URI and browser-origin policies.

  Configuration lives under `config :mc_emcomm, :mcp` and is read from the
  environment in `config/runtime.exs`. Everything else in this namespace —
  `McEmcomm.OAuth.Clients`, `AuthorizationCodes`, `Tokens`, `Scopes`, `PKCE` —
  is a hand-rolled implementation of the subset of OAuth 2.1 that MCP clients
  use: authorization code with PKCE (S256 only), resource indicators
  (RFC 8707), dynamic client registration (RFC 7591), token revocation
  (RFC 7009), and the RFC 8414 / RFC 9728 metadata documents.
  """

  @loopback_hosts ["127.0.0.1", "localhost", "::1"]

  @doc "Whether the connector is switched on (`MC_EMCOMM_MCP_ENABLED`)."
  @spec enabled?() :: boolean()
  def enabled?, do: config(:enabled)

  @doc "The authorization server's issuer identifier (`MC_EMCOMM_OAUTH_ISSUER`)."
  @spec issuer() :: String.t()
  def issuer, do: config(:issuer)

  @doc "The canonical MCP endpoint URL and token audience (`MC_EMCOMM_MCP_RESOURCE_URL`)."
  @spec resource_url() :: String.t()
  def resource_url, do: config(:resource_url)

  @doc "Seconds an access token lives."
  @spec access_token_ttl() :: pos_integer()
  def access_token_ttl, do: config(:access_token_ttl)

  @doc "Seconds a refresh token lives."
  @spec refresh_token_ttl() :: pos_integer()
  def refresh_token_ttl, do: config(:refresh_token_ttl)

  @doc "Seconds an authorization code stays redeemable."
  @spec auth_code_ttl() :: pos_integer()
  def auth_code_ttl, do: config(:auth_code_ttl)

  @doc "Requests per minute allowed per token on `/mcp` and per IP on the OAuth endpoints."
  @spec rate_limit() :: pos_integer()
  def rate_limit, do: config(:rate_limit)

  @doc "The URL of the RFC 9728 protected resource metadata document."
  @spec protected_resource_metadata_url() :: String.t()
  def protected_resource_metadata_url, do: issuer() <> "/.well-known/oauth-protected-resource"

  @doc "RFC 9728 protected resource metadata for the MCP endpoint."
  @spec protected_resource_metadata() :: map()
  def protected_resource_metadata do
    %{
      "resource" => resource_url(),
      "authorization_servers" => [issuer()],
      "scopes_supported" => McEmcomm.OAuth.Scopes.all(),
      "bearer_methods_supported" => ["header"],
      "resource_name" => "Monroe County ARES/RACES MCP connector"
    }
  end

  @doc "RFC 8414 authorization server metadata."
  @spec authorization_server_metadata() :: map()
  def authorization_server_metadata do
    issuer = issuer()

    %{
      "issuer" => issuer,
      "authorization_endpoint" => issuer <> "/oauth/authorize",
      "token_endpoint" => issuer <> "/oauth/token",
      "registration_endpoint" => issuer <> "/oauth/register",
      "revocation_endpoint" => issuer <> "/oauth/revoke",
      "scopes_supported" => McEmcomm.OAuth.Scopes.all(),
      "response_types_supported" => ["code"],
      "response_modes_supported" => ["query"],
      "grant_types_supported" => ["authorization_code", "refresh_token"],
      "code_challenge_methods_supported" => ["S256"],
      "token_endpoint_auth_methods_supported" => token_endpoint_auth_methods(),
      "revocation_endpoint_auth_methods_supported" => token_endpoint_auth_methods(),
      "authorization_response_iss_parameter_supported" => true
    }
  end

  @doc "Client authentication methods the token and revocation endpoints accept."
  @spec token_endpoint_auth_methods() :: [String.t()]
  def token_endpoint_auth_methods, do: ["none", "client_secret_post", "client_secret_basic"]

  @doc """
  Whether a redirect URI may be registered: one of the configured exact-match
  URIs (Claude's hosted callbacks) or an `http` loopback URI on any port and
  path (RFC 8252 §7.3), which is what Claude Code and the MCP Inspector use.
  Fragments are never allowed.
  """
  @spec allowed_redirect_uri?(String.t()) :: boolean()
  def allowed_redirect_uri?(uri) when is_binary(uri) do
    uri in config(:redirect_uris) or loopback_redirect_uri?(uri)
  end

  def allowed_redirect_uri?(_uri), do: false

  @doc """
  Whether `presented` matches `registered`: exact string equality, except
  that a registered loopback URI matches any port (RFC 8252 §7.3, the
  ephemeral-port callback native clients use).
  """
  @spec redirect_uri_matches?(String.t(), String.t()) :: boolean()
  def redirect_uri_matches?(registered, presented) when registered == presented, do: true

  def redirect_uri_matches?(registered, presented)
      when is_binary(registered) and is_binary(presented) do
    with true <- loopback_redirect_uri?(registered),
         true <- loopback_redirect_uri?(presented),
         %URI{} = reg <- URI.parse(registered),
         %URI{} = pres <- URI.parse(presented) do
      reg.host == pres.host and reg.path == pres.path and reg.query == pres.query
    else
      _ -> false
    end
  end

  def redirect_uri_matches?(_registered, _presented), do: false

  @doc "Whether the URI is `http://` to a loopback host (any port, any path, no fragment)."
  @spec loopback_redirect_uri?(String.t()) :: boolean()
  def loopback_redirect_uri?(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: "http", host: host, fragment: nil} when host in @loopback_hosts -> true
      _ -> false
    end
  end

  def loopback_redirect_uri?(_uri), do: false

  @doc """
  Whether a browser `Origin` may reach the connector: the app's own origin,
  the issuer, the configured Claude origins, or any loopback origin (the MCP
  Inspector runs in the browser on a local port).
  """
  @spec allowed_origin?(String.t()) :: boolean()
  def allowed_origin?(origin) when is_binary(origin) do
    origin in own_origins() or origin in config(:allowed_origins) or loopback_origin?(origin)
  end

  def allowed_origin?(_origin), do: false

  defp own_origins do
    endpoint = McEmcommWeb.Endpoint.url()

    [endpoint, origin_of(issuer()), origin_of(resource_url())]
    |> Enum.reject(&is_nil/1)
  end

  defp origin_of(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port} when is_binary(scheme) and is_binary(host) ->
        URI.to_string(%URI{scheme: scheme, host: host, port: port})

      _not_absolute ->
        nil
    end
  end

  defp loopback_origin?(origin) do
    case URI.parse(origin) do
      %URI{scheme: scheme, host: host, path: path}
      when scheme in ["http", "https"] and host in @loopback_hosts and path in [nil, ""] ->
        true

      _ ->
        false
    end
  end

  @doc "SHA-256 digest of a secret, code, or token — the only form ever stored."
  @spec hash(binary()) :: binary()
  def hash(secret) when is_binary(secret), do: :crypto.hash(:sha256, secret)

  @doc "A fresh 32-byte random secret, URL-safe base64 without padding."
  @spec random_secret() :: String.t()
  def random_secret, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc false
  @spec config(atom()) :: term()
  def config(key), do: :mc_emcomm |> Application.fetch_env!(:mcp) |> Keyword.fetch!(key)
end

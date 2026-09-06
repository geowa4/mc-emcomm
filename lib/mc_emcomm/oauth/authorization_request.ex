defmodule McEmcomm.OAuth.AuthorizationRequest do
  @moduledoc """
  Validates the query string of `GET /oauth/authorize` before the consent
  screen renders anything.

  Two classes of failure are kept apart on purpose (OAuth 2.1 §4.1.2.1): a
  bad `client_id` or an unregistered `redirect_uri` is *fatal* — the user
  sees an error page and is never redirected anywhere; every other problem
  is reported back to the client's verified redirect URI as an OAuth error
  response.
  """

  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.Client
  alias McEmcomm.OAuth.Clients
  alias McEmcomm.OAuth.PKCE
  alias McEmcomm.OAuth.Scopes

  @type t :: %__MODULE__{
          client: Client.t(),
          redirect_uri: String.t(),
          code_challenge: String.t(),
          resource: String.t(),
          scopes: [String.t()],
          state: String.t() | nil
        }

  defstruct [:client, :redirect_uri, :code_challenge, :resource, :scopes, :state]

  @type fatal :: :invalid_client | :invalid_redirect_uri
  @type redirect_error :: {:redirect, String.t(), String.t(), String.t(), String.t() | nil}

  @doc """
  Validates the request. `{:error, fatal}` must render an error page;
  `{:error, {:redirect, redirect_uri, error, description, state}}` must
  redirect the browser to the client with those parameters.
  """
  @spec validate(map()) :: {:ok, t()} | {:error, fatal() | redirect_error()}
  def validate(params) when is_map(params) do
    with {:ok, client} <- fetch_client(params["client_id"]),
         {:ok, redirect_uri} <- check_redirect_uri(client, params["redirect_uri"]) do
      state = string_or_nil(params["state"])

      case check_request(params) do
        {:ok, request} ->
          {:ok, %{request | client: client, redirect_uri: redirect_uri, state: state}}

        {:error, error, description} ->
          {:error, {:redirect, redirect_uri, error, description, state}}
      end
    end
  end

  defp fetch_client(client_id) do
    case Clients.fetch(client_id) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, :invalid_client}
    end
  end

  defp check_redirect_uri(client, uri) do
    if is_binary(uri) and Clients.redirect_uri_allowed?(client, uri),
      do: {:ok, uri},
      else: {:error, :invalid_redirect_uri}
  end

  defp check_request(params) do
    with :ok <- check_response_type(params["response_type"]),
         :ok <- check_pkce(params["code_challenge"], params["code_challenge_method"]),
         :ok <- check_resource(params["resource"]),
         {:ok, scopes} <- check_scope(params["scope"]) do
      {:ok,
       %__MODULE__{
         code_challenge: params["code_challenge"],
         resource: params["resource"],
         scopes: scopes
       }}
    end
  end

  defp check_response_type("code"), do: :ok

  defp check_response_type(_other),
    do: {:error, "unsupported_response_type", "response_type must be \"code\""}

  defp check_pkce(challenge, method) do
    cond do
      not PKCE.valid_method?(method) ->
        {:error, "invalid_request", "code_challenge_method must be S256"}

      not PKCE.valid_challenge?(challenge) ->
        {:error, "invalid_request", "code_challenge is missing or malformed"}

      true ->
        :ok
    end
  end

  # RFC 8707: the token must be requested for this MCP server, named exactly.
  defp check_resource(resource) do
    if is_binary(resource) and resource == OAuth.resource_url(),
      do: :ok,
      else: {:error, "invalid_target", "resource must be #{OAuth.resource_url()}"}
  end

  defp check_scope(scope) do
    case Scopes.parse(scope) do
      {:ok, scopes} -> {:ok, scopes}
      {:error, :invalid_scope} -> {:error, "invalid_scope", "unknown scope requested"}
    end
  end

  defp string_or_nil(value) when is_binary(value) and value != "", do: value
  defp string_or_nil(_value), do: nil

  @doc "The redirect URL that hands the authorization code to the client (with RFC 9207 `iss`)."
  @spec success_url(t(), String.t()) :: String.t()
  def success_url(%__MODULE__{redirect_uri: uri, state: state}, code) do
    append_query(uri, [{"code", code}, {"state", state}, {"iss", OAuth.issuer()}])
  end

  @doc "The redirect URL that reports an OAuth error to the client."
  @spec error_url(String.t(), String.t(), String.t(), String.t() | nil) :: String.t()
  def error_url(redirect_uri, error, description, state) do
    append_query(redirect_uri, [
      {"error", error},
      {"error_description", description},
      {"state", state},
      {"iss", OAuth.issuer()}
    ])
  end

  defp append_query(uri, pairs) do
    parsed = URI.parse(uri)
    existing = if parsed.query, do: URI.decode_query(parsed.query), else: %{}

    added = for {k, v} <- pairs, not is_nil(v), into: %{}, do: {k, v}

    URI.to_string(%{parsed | query: URI.encode_query(Map.merge(existing, added))})
  end
end

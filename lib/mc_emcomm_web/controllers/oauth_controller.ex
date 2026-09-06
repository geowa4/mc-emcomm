defmodule McEmcommWeb.OAuthController do
  @moduledoc """
  The machine-facing half of the authorization server (SPEC.md §28): the two
  discovery documents, RFC 7591 client registration, the token endpoint
  (authorization code with PKCE, refresh with rotation), and RFC 7009
  revocation. The browser-facing half — the consent screen at
  `/oauth/authorize` — is `McEmcommWeb.OAuthLive.Consent`.

  Every response here is JSON. Token responses are `Cache-Control: no-store`.
  `invalid_client` is always a 401 so that a Claude connection whose
  dynamically registered client has disappeared re-registers instead of
  retrying forever.
  """
  use McEmcommWeb, :controller

  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.AuthorizationCodes
  alias McEmcomm.OAuth.Clients
  alias McEmcomm.OAuth.Tokens

  @metadata_cache "public, max-age=300"

  @doc "CORS preflight for the JSON endpoints; the headers come from `McEmcommWeb.Plugs.MCPCors`."
  def preflight(conn, _params), do: send_resp(conn, 204, "")

  @doc "RFC 9728 protected resource metadata."
  def protected_resource_metadata(conn, _params) do
    conn
    |> put_resp_header("cache-control", @metadata_cache)
    |> json(OAuth.protected_resource_metadata())
  end

  @doc "RFC 8414 authorization server metadata."
  def authorization_server_metadata(conn, _params) do
    conn
    |> put_resp_header("cache-control", @metadata_cache)
    |> json(OAuth.authorization_server_metadata())
  end

  @doc "RFC 7591 dynamic client registration."
  def register(conn, params) do
    case Clients.register(Map.drop(params, ["client_id", "client_secret"])) do
      {:ok, client, raw_secret} ->
        emit(:register, :ok)

        conn
        |> put_status(201)
        |> put_resp_header("cache-control", "no-store")
        |> json(Clients.registration_response(client, raw_secret))

      {:error, changeset} ->
        emit(:register, :error)
        {error, description} = registration_error(changeset)
        oauth_error(conn, 400, error, description)
    end
  end

  defp registration_error(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Regex.replace(~r"%{(\w+)}", message, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    description =
      Enum.map_join(errors, "; ", fn {field, messages} ->
        "#{field} #{Enum.join(messages, ", ")}"
      end)

    if Map.has_key?(errors, :redirect_uris),
      do: {"invalid_redirect_uri", description},
      else: {"invalid_client_metadata", description}
  end

  @doc "The token endpoint: `authorization_code` and `refresh_token` grants."
  def token(conn, params) do
    case authenticate_client(conn, params) do
      {:ok, client} ->
        grant(conn, client, params)

      {:error, :invalid_client} ->
        emit(:token, :invalid_client)
        oauth_error(conn, 401, "invalid_client", "Unknown client or bad client credentials.")
    end
  end

  defp grant(conn, client, %{"grant_type" => "authorization_code"} = params) do
    redemption = %{
      client_id: client.client_id,
      redirect_uri: params["redirect_uri"],
      code_verifier: params["code_verifier"],
      resource: params["resource"]
    }

    case AuthorizationCodes.redeem(params["code"], redemption) do
      {:ok, code} ->
        {:ok, issued} = Tokens.issue(code.user, client.client_id, code.scopes, code.resource)
        emit(:token, :ok)
        token_response(conn, issued)

      {:error, :invalid_grant} ->
        emit(:token, :invalid_grant)

        oauth_error(
          conn,
          400,
          "invalid_grant",
          "The authorization code is invalid, expired, already used, or does not match " <>
            "the client, redirect URI, PKCE verifier, or resource it was issued for."
        )
    end
  end

  defp grant(conn, client, %{"grant_type" => "refresh_token"} = params) do
    case Tokens.refresh(params["refresh_token"], client.client_id) do
      {:ok, issued} ->
        emit(:refresh, :ok)
        token_response(conn, issued)

      {:error, :invalid_grant} ->
        emit(:refresh, :invalid_grant)

        oauth_error(
          conn,
          400,
          "invalid_grant",
          "The refresh token is invalid, expired, revoked, or was already used."
        )
    end
  end

  defp grant(conn, _client, %{"grant_type" => other}) when is_binary(other) do
    oauth_error(
      conn,
      400,
      "unsupported_grant_type",
      "grant_type must be authorization_code or refresh_token."
    )
  end

  defp grant(conn, _client, _params) do
    oauth_error(conn, 400, "invalid_request", "grant_type is required.")
  end

  @doc "RFC 7009 token revocation. Always 200 for an authenticated client."
  def revoke(conn, params) do
    case authenticate_client(conn, params) do
      {:ok, client} ->
        Tokens.revoke(params["token"], client.client_id)
        emit(:revoke, :ok)

        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{})

      {:error, :invalid_client} ->
        emit(:revoke, :invalid_client)
        oauth_error(conn, 401, "invalid_client", "Unknown client or bad client credentials.")
    end
  end

  # Client credentials arrive as `client_id`/`client_secret` form fields
  # (`client_secret_post`, or `none` with no secret) or as HTTP Basic.
  defp authenticate_client(conn, params) do
    {client_id, secret} =
      case basic_credentials(conn) do
        {id, secret} -> {id, secret}
        nil -> {params["client_id"], params["client_secret"]}
      end

    with {:ok, client} <- Clients.fetch(client_id),
         :ok <- Clients.authenticate(client, secret) do
      {:ok, client}
    else
      _ -> {:error, :invalid_client}
    end
  end

  defp basic_credentials(conn) do
    with ["Basic " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [id, secret] <- String.split(decoded, ":", parts: 2) do
      {URI.decode_www_form(id), URI.decode_www_form(secret)}
    else
      _ -> nil
    end
  end

  defp token_response(conn, issued) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> json(%{
      "access_token" => issued.access_token,
      "token_type" => issued.token_type,
      "expires_in" => issued.expires_in,
      "refresh_token" => issued.refresh_token,
      "scope" => issued.scope
    })
  end

  defp oauth_error(conn, status, error, description) do
    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{"error" => error, "error_description" => description})
  end

  defp emit(operation, outcome) do
    :telemetry.execute([:mc_emcomm, :mcp, :oauth], %{count: 1}, %{
      operation: operation,
      outcome: outcome
    })
  end
end

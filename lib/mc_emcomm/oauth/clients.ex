defmodule McEmcomm.OAuth.Clients do
  @moduledoc """
  OAuth client registration and authentication: RFC 7591 dynamic clients in
  `oauth_clients`, plus the optional static client from
  `MC_EMCOMM_MCP_STATIC_CLIENT_ID` / `_SECRET` for Claude's "Advanced
  settings" path. Raw secrets are returned exactly once, at registration, and
  only their SHA-256 digest is stored.
  """

  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.Client
  alias McEmcomm.Repo

  @static_client_name "Pre-configured client"
  @default_auth_method "client_secret_basic"

  @doc """
  Registers a client. Returns the client and its raw secret (`nil` for a
  public client using `token_endpoint_auth_method: "none"`).
  """
  @spec register(map()) :: {:ok, Client.t(), String.t() | nil} | {:error, Ecto.Changeset.t()}
  def register(attrs) when is_map(attrs) do
    attrs = attrs |> Map.new(fn {k, v} -> {to_string(k), v} end) |> put_defaults()
    changeset = Client.registration_changeset(%Client{}, attrs)

    {hashed_secret, raw_secret} =
      case Ecto.Changeset.get_field(changeset, :token_endpoint_auth_method) do
        "none" ->
          {nil, nil}

        _confidential ->
          raw = OAuth.random_secret()
          {OAuth.hash(raw), raw}
      end

    changeset
    |> Ecto.Changeset.put_change(:client_id, OAuth.random_secret())
    |> Ecto.Changeset.put_change(:hashed_secret, hashed_secret)
    |> Repo.insert()
    |> case do
      {:ok, client} -> {:ok, client, raw_secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp put_defaults(attrs) do
    attrs
    |> Map.put_new("token_endpoint_auth_method", @default_auth_method)
    |> Map.put_new("grant_types", ["authorization_code", "refresh_token"])
    |> Map.put_new("response_types", ["code"])
    |> Map.update("grant_types", [], &List.wrap/1)
    |> Map.update("response_types", [], &List.wrap/1)
    |> Map.update("redirect_uris", [], &List.wrap/1)
  end

  @doc "Looks a client up by `client_id`: the static client first, then the table."
  @spec fetch(term()) :: {:ok, Client.t()} | :error
  def fetch(client_id) when is_binary(client_id) and client_id != "" do
    case static_client() do
      %Client{client_id: ^client_id} = client -> {:ok, client}
      _other -> fetch_registered(client_id)
    end
  end

  def fetch(_client_id), do: :error

  defp fetch_registered(client_id) do
    case Repo.get_by(Client, client_id: client_id) do
      nil -> :error
      client -> {:ok, client}
    end
  end

  @doc """
  Verifies the client's credentials for the token and revocation endpoints.
  A public client (`none`) must present no secret; a confidential client
  must present the matching one. Compared in constant time on the digests.
  """
  @spec authenticate(Client.t(), String.t() | nil) :: :ok | {:error, :invalid_client}
  def authenticate(%Client{token_endpoint_auth_method: "none"}, secret)
      when secret in [nil, ""],
      do: :ok

  def authenticate(%Client{token_endpoint_auth_method: "none"}, _secret),
    do: {:error, :invalid_client}

  def authenticate(%Client{hashed_secret: hashed}, secret)
      when is_binary(hashed) and is_binary(secret) and secret != "" do
    if Plug.Crypto.secure_compare(hashed, OAuth.hash(secret)),
      do: :ok,
      else: {:error, :invalid_client}
  end

  def authenticate(%Client{}, _secret), do: {:error, :invalid_client}

  @doc """
  Whether the client may be sent to `redirect_uri`: exact match against a
  registered URI (loopback URIs match on any port), or, for the static
  client, anything the registration allowlist accepts.
  """
  @spec redirect_uri_allowed?(Client.t(), term()) :: boolean()
  def redirect_uri_allowed?(%Client{id: nil}, uri), do: OAuth.allowed_redirect_uri?(uri)

  def redirect_uri_allowed?(%Client{redirect_uris: registered}, uri) when is_binary(uri) do
    Enum.any?(registered, &OAuth.redirect_uri_matches?(&1, uri))
  end

  def redirect_uri_allowed?(%Client{}, _uri), do: false

  @doc "The client configured from the environment, or `nil` when none is."
  @spec static_client() :: Client.t() | nil
  def static_client do
    case OAuth.config(:static_client_id) do
      id when is_binary(id) and id != "" ->
        secret = OAuth.config(:static_client_secret)

        %Client{
          client_id: id,
          client_name: @static_client_name,
          hashed_secret: if(is_binary(secret) and secret != "", do: OAuth.hash(secret)),
          token_endpoint_auth_method:
            if(is_binary(secret) and secret != "", do: "client_secret_post", else: "none"),
          redirect_uris: OAuth.config(:redirect_uris)
        }

      _unset ->
        nil
    end
  end

  @doc "The RFC 7591 registration response body for a client."
  @spec registration_response(Client.t(), String.t() | nil) :: map()
  def registration_response(%Client{} = client, raw_secret) do
    base = %{
      "client_id" => client.client_id,
      "client_id_issued_at" => DateTime.to_unix(client.inserted_at),
      "client_name" => client.client_name,
      "redirect_uris" => client.redirect_uris,
      "token_endpoint_auth_method" => client.token_endpoint_auth_method,
      "grant_types" => client.grant_types,
      "response_types" => client.response_types,
      "application_type" => client.application_type
    }

    base = Map.reject(base, fn {_k, v} -> is_nil(v) end)

    case raw_secret do
      nil -> base
      secret -> Map.merge(base, %{"client_secret" => secret, "client_secret_expires_at" => 0})
    end
  end
end

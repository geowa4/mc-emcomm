defmodule McEmcommWeb.Plugs.MCPAuth do
  @moduledoc """
  Bearer-token authentication for `POST /mcp` (SPEC.md §28). The token is
  hashed and looked up; it must be a live access token whose audience equals
  `MC_EMCOMM_MCP_RESOURCE_URL` exactly. Missing or invalid tokens are
  answered 401 with a `WWW-Authenticate` challenge that points at the
  protected resource metadata, which is how an MCP client discovers the
  authorization server. On success the caller's `McEmcomm.MCP.Context` is
  assigned as `:mcp_context`.

  Raw token values are never logged; the challenge never says whether a
  token existed.
  """
  @behaviour Plug

  import Plug.Conn

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.MCP.Context
  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.Tokens

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, raw} <- bearer(conn),
         {:ok, token} <- Tokens.verify_access(raw, OAuth.resource_url()) do
      context = %Context{
        scope: Scope.for_user(token.user),
        scopes: token.scopes,
        client_id: token.client_id,
        token_id: token.id
      }

      assign(conn, :mcp_context, context)
    else
      {:error, :missing} -> unauthorized(conn, nil)
      {:error, :invalid_token} -> unauthorized(conn, "invalid_token")
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      [value | _] -> parse_bearer(String.split(value, " ", parts: 2, trim: true))
      [] -> {:error, :missing}
    end
  end

  defp parse_bearer([scheme, token]) when byte_size(token) > 0 do
    if String.downcase(scheme) == "bearer", do: {:ok, token}, else: {:error, :invalid_token}
  end

  defp parse_bearer(_parts), do: {:error, :invalid_token}

  @doc "Sends the 401 challenge (RFC 6750 §3 / RFC 9728 §5.1)."
  @spec unauthorized(Plug.Conn.t(), String.t() | nil) :: Plug.Conn.t()
  def unauthorized(conn, error) do
    params = [~s(resource_metadata="#{OAuth.protected_resource_metadata_url()}")]
    params = if error, do: [~s(error="#{error}") | params], else: params

    conn
    |> put_resp_header("www-authenticate", "Bearer " <> Enum.join(params, ", "))
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(
      401,
      Jason.encode!(%{
        "error" => error || "unauthorized",
        "error_description" => "A valid bearer token for #{OAuth.resource_url()} is required."
      })
    )
    |> halt()
  end

  @doc "Sends the 403 `insufficient_scope` challenge naming the scope the operation needs."
  @spec insufficient_scope(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def insufficient_scope(conn, scope) do
    challenge =
      ~s(Bearer error="insufficient_scope", scope="#{scope}", ) <>
        ~s(resource_metadata="#{OAuth.protected_resource_metadata_url()}")

    conn
    |> put_resp_header("www-authenticate", challenge)
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(
      403,
      Jason.encode!(%{
        "error" => "insufficient_scope",
        "scope" => scope,
        "error_description" => "This operation requires the #{scope} scope."
      })
    )
    |> halt()
  end
end

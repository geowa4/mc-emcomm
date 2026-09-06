defmodule McEmcomm.OAuth.PKCE do
  @moduledoc """
  Proof Key for Code Exchange (RFC 7636), `S256` only. The `plain` method is
  rejected outright: every MCP client sends S256, and plain would let anyone
  who saw the authorization request redeem the code.
  """

  @method "S256"
  @verifier_format ~r/^[A-Za-z0-9\-._~]{43,128}$/
  @challenge_format ~r/^[A-Za-z0-9\-_]{43}$/

  @doc "The only supported `code_challenge_method`."
  @spec method() :: String.t()
  def method, do: @method

  @doc "Whether the `code_challenge_method` parameter is acceptable."
  @spec valid_method?(term()) :: boolean()
  def valid_method?(@method), do: true
  def valid_method?(_method), do: false

  @doc "Whether the `code_challenge` is a well-formed S256 challenge (43 URL-safe base64 chars)."
  @spec valid_challenge?(term()) :: boolean()
  def valid_challenge?(challenge) when is_binary(challenge),
    do: Regex.match?(@challenge_format, challenge)

  def valid_challenge?(_challenge), do: false

  @doc """
  Whether `verifier` is the pre-image of `challenge`:
  `BASE64URL(SHA256(verifier)) == challenge`, compared in constant time.
  """
  @spec verify(term(), term()) :: boolean()
  def verify(verifier, challenge) when is_binary(verifier) and is_binary(challenge) do
    Regex.match?(@verifier_format, verifier) and
      Plug.Crypto.secure_compare(challenge(verifier), challenge)
  end

  def verify(_verifier, _challenge), do: false

  @doc "The S256 challenge for a verifier (used by tests and the consent flow docs)."
  @spec challenge(String.t()) :: String.t()
  def challenge(verifier) when is_binary(verifier) do
    :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
  end
end

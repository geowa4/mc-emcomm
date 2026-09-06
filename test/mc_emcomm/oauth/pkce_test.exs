defmodule McEmcomm.OAuth.PKCETest do
  use ExUnit.Case, async: true

  alias McEmcomm.OAuth.PKCE
  alias McEmcomm.OAuthFixtures

  test "S256 is the only accepted method; plain is rejected" do
    assert PKCE.valid_method?("S256")
    refute PKCE.valid_method?("plain")
    refute PKCE.valid_method?(nil)
  end

  test "verify/2 accepts the verifier's own challenge and nothing else" do
    %{verifier: verifier, challenge: challenge} = OAuthFixtures.pkce_fixture()
    assert PKCE.verify(verifier, challenge)
    refute PKCE.verify(verifier <> "x", challenge)
    refute PKCE.verify("too-short", PKCE.challenge("too-short"))
    refute PKCE.verify(nil, challenge)
  end

  test "valid_challenge?/1 wants 43 URL-safe base64 characters" do
    assert PKCE.valid_challenge?(OAuthFixtures.pkce_fixture().challenge)
    refute PKCE.valid_challenge?("abc")
    refute PKCE.valid_challenge?(String.duplicate("+", 43))
  end
end

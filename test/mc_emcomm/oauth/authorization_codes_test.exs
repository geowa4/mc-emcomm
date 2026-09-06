defmodule McEmcomm.OAuth.AuthorizationCodesTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.AuthorizationCode
  alias McEmcomm.OAuth.AuthorizationCodes
  alias McEmcomm.OAuthFixtures

  setup do
    member = McEmcommFixtures.member_fixture()
    client = OAuthFixtures.public_client_fixture()
    {code, grant} = OAuthFixtures.authorization_code_fixture(member.user, client)
    %{user: member.user, client: client, code: code, grant: grant}
  end

  test "codes are stored hashed with their binding", %{code: code, grant: grant, user: user} do
    [row] = Repo.all(AuthorizationCode)
    assert row.hashed_code == OAuth.hash(code)
    refute row.hashed_code == code
    assert row.user_id == user.id
    assert row.client_id == grant.client_id
    assert row.redirect_uri == grant.redirect_uri
    assert row.resource == grant.resource
    assert row.scopes == ["emcomm:member", "emcomm:operations"]
    assert DateTime.diff(row.expires_at, DateTime.utc_now()) in 55..60
  end

  test "a matching request redeems the code exactly once", %{code: code, grant: grant} do
    assert {:ok, redeemed} = AuthorizationCodes.redeem(code, grant)
    assert redeemed.user.id
    assert redeemed.scopes == ["emcomm:member", "emcomm:operations"]
    assert AuthorizationCodes.redeem(code, grant) == {:error, :invalid_grant}
  end

  test "a wrong code_verifier is rejected", %{code: code, grant: grant} do
    other = OAuthFixtures.pkce_fixture()

    assert AuthorizationCodes.redeem(code, %{grant | code_verifier: other.verifier}) ==
             {:error, :invalid_grant}
  end

  test "an inexact redirect URI is rejected", %{code: code, grant: grant} do
    assert AuthorizationCodes.redeem(code, %{grant | redirect_uri: grant.redirect_uri <> "/"}) ==
             {:error, :invalid_grant}
  end

  test "another client cannot redeem it", %{code: code, grant: grant} do
    assert AuthorizationCodes.redeem(code, %{grant | client_id: "someone-else"}) ==
             {:error, :invalid_grant}
  end

  test "a mismatched resource is rejected but an omitted one is not", %{code: code, grant: grant} do
    assert AuthorizationCodes.redeem(code, %{grant | resource: "https://other.example/mcp"}) ==
             {:error, :invalid_grant}

    assert {:ok, _} = AuthorizationCodes.redeem(code, Map.delete(grant, :resource))
  end

  test "codes expire after 60 seconds", %{code: code, grant: grant} do
    Repo.update_all(AuthorizationCode,
      set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
    )

    assert AuthorizationCodes.redeem(code, grant) == {:error, :invalid_grant}
  end

  test "unknown codes are invalid", %{grant: grant} do
    assert AuthorizationCodes.redeem("nope", grant) == {:error, :invalid_grant}
    assert AuthorizationCodes.redeem(nil, grant) == {:error, :invalid_grant}
  end
end

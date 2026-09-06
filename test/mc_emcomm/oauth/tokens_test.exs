defmodule McEmcomm.OAuth.TokensTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members
  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.Token
  alias McEmcomm.OAuth.Tokens
  alias McEmcomm.OAuthFixtures

  setup do
    member = McEmcommFixtures.member_fixture()

    %{
      member: member,
      user: member.user,
      issued: OAuthFixtures.tokens_fixture(member.user, client_id: "c1")
    }
  end

  test "tokens are opaque and stored hashed", %{issued: issued} do
    rows = Repo.all(Token)
    assert length(rows) == 2
    hashes = Enum.map(rows, & &1.hashed_token)
    assert OAuth.hash(issued.access_token) in hashes
    assert OAuth.hash(issued.refresh_token) in hashes
    refute issued.access_token in hashes
    assert [family] = rows |> Enum.map(& &1.family_id) |> Enum.uniq()
    assert family
  end

  test "the response shape is an OAuth token response", %{issued: issued} do
    assert issued.token_type == "Bearer"
    assert issued.expires_in == OAuth.access_token_ttl()
    assert issued.scope == "emcomm:member emcomm:operations"
  end

  describe "verify_access/2" do
    test "accepts a live access token for the exact audience", %{issued: issued, user: user} do
      assert {:ok, token} = Tokens.verify_access(issued.access_token, OAuth.resource_url())
      assert token.user.id == user.id
      assert token.scopes == ["emcomm:member", "emcomm:operations"]
    end

    test "rejects an audience mismatch, even a near miss", %{issued: issued} do
      assert Tokens.verify_access(issued.access_token, OAuth.resource_url() <> "/") ==
               {:error, :invalid_token}

      assert Tokens.verify_access(issued.access_token, "https://other.example/mcp") ==
               {:error, :invalid_token}
    end

    test "rejects refresh tokens, expired tokens, revoked tokens, and garbage", %{issued: issued} do
      assert Tokens.verify_access(issued.refresh_token, OAuth.resource_url()) ==
               {:error, :invalid_token}

      Repo.update_all(Token,
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
      )

      assert Tokens.verify_access(issued.access_token, OAuth.resource_url()) ==
               {:error, :invalid_token}

      assert Tokens.verify_access("nope", OAuth.resource_url()) == {:error, :invalid_token}
      assert Tokens.verify_access(nil, OAuth.resource_url()) == {:error, :invalid_token}
    end
  end

  describe "refresh/2" do
    test "rotates: the old refresh token dies and a new pair in the same family is issued", %{
      issued: issued
    } do
      assert {:ok, next} = Tokens.refresh(issued.refresh_token, "c1")
      refute next.refresh_token == issued.refresh_token
      assert {:ok, _} = Tokens.verify_access(next.access_token, OAuth.resource_url())

      old = Repo.get_by!(Token, hashed_token: OAuth.hash(issued.refresh_token))
      new = Repo.get_by!(Token, hashed_token: OAuth.hash(next.refresh_token))
      assert old.revoked_at
      assert new.family_id == old.family_id
    end

    test "reusing a rotated refresh token revokes the whole family", %{issued: issued} do
      {:ok, next} = Tokens.refresh(issued.refresh_token, "c1")
      assert Tokens.refresh(issued.refresh_token, "c1") == {:error, :invalid_grant}

      assert Tokens.verify_access(next.access_token, OAuth.resource_url()) ==
               {:error, :invalid_token}

      assert Tokens.refresh(next.refresh_token, "c1") == {:error, :invalid_grant}
      assert Enum.all?(Repo.all(Token), & &1.revoked_at)
    end

    test "another client, an expired token, or an access token cannot refresh", %{issued: issued} do
      assert Tokens.refresh(issued.refresh_token, "c2") == {:error, :invalid_grant}
      assert Tokens.refresh(issued.access_token, "c1") == {:error, :invalid_grant}

      Repo.update_all(Token,
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
      )

      assert Tokens.refresh(issued.refresh_token, "c1") == {:error, :invalid_grant}
    end

    test "scopes are re-intersected with the live role on refresh", %{
      issued: issued,
      member: member
    } do
      admin = McEmcommFixtures.admin_scope_fixture().user
      {:ok, _} = Members.transition_status(member, :inactive, admin, "moved away")

      assert Tokens.refresh(issued.refresh_token, "c1") == {:error, :invalid_grant}
    end
  end

  describe "revoke/2" do
    test "an access token is revoked alone; a refresh token takes its family", %{issued: issued} do
      assert :ok = Tokens.revoke(issued.access_token, "c1")

      assert Tokens.verify_access(issued.access_token, OAuth.resource_url()) ==
               {:error, :invalid_token}

      assert {:ok, next} = Tokens.refresh(issued.refresh_token, "c1")

      assert :ok = Tokens.revoke(next.refresh_token, "c1")

      assert Tokens.verify_access(next.access_token, OAuth.resource_url()) ==
               {:error, :invalid_token}
    end

    test "another client's token and unknown tokens are ignored", %{issued: issued} do
      assert :ok = Tokens.revoke(issued.access_token, "c2")
      assert {:ok, _} = Tokens.verify_access(issued.access_token, OAuth.resource_url())
      assert :ok = Tokens.revoke("nope", "c1")
    end
  end
end

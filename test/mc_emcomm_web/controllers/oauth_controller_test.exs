defmodule McEmcommWeb.OAuthControllerTest do
  use McEmcommWeb.ConnCase, async: true

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.Token
  alias McEmcomm.OAuthFixtures
  alias McEmcomm.Repo

  describe "discovery" do
    test "protected resource metadata names the resource and the authorization server", %{
      conn: conn
    } do
      for path <- [
            ~p"/.well-known/oauth-protected-resource",
            ~p"/.well-known/oauth-protected-resource/mcp"
          ] do
        body = conn |> get(path) |> json_response(200)
        assert body["resource"] == OAuth.resource_url()
        assert body["resource"] == "http://localhost:4002/mcp"
        assert body["authorization_servers"] == [OAuth.issuer()]

        assert body["scopes_supported"] == [
                 "emcomm:member",
                 "emcomm:operations",
                 "emcomm:membership"
               ]

        assert body["bearer_methods_supported"] == ["header"]
      end
    end

    test "authorization server metadata advertises the endpoints, S256, and both grants", %{
      conn: conn
    } do
      body = conn |> get(~p"/.well-known/oauth-authorization-server") |> json_response(200)
      assert body["issuer"] == OAuth.issuer()
      assert body["authorization_endpoint"] == OAuth.issuer() <> "/oauth/authorize"
      assert body["token_endpoint"] == OAuth.issuer() <> "/oauth/token"
      assert body["registration_endpoint"] == OAuth.issuer() <> "/oauth/register"
      assert body["revocation_endpoint"] == OAuth.issuer() <> "/oauth/revoke"
      assert body["response_types_supported"] == ["code"]
      assert body["grant_types_supported"] == ["authorization_code", "refresh_token"]
      assert body["code_challenge_methods_supported"] == ["S256"]
      assert "none" in body["token_endpoint_auth_methods_supported"]
      assert "client_secret_post" in body["token_endpoint_auth_methods_supported"]
      assert body["authorization_response_iss_parameter_supported"] == true
    end

    test "browser origins that are allowed get CORS headers; others get none", %{conn: conn} do
      allowed =
        conn
        |> put_req_header("origin", "https://claude.ai")
        |> get(~p"/.well-known/oauth-authorization-server")

      assert get_resp_header(allowed, "access-control-allow-origin") == ["https://claude.ai"]
      refute get_resp_header(allowed, "access-control-allow-origin") == ["*"]

      preflight =
        conn |> put_req_header("origin", "http://localhost:6274") |> options(~p"/oauth/token")

      assert response(preflight, 204)

      assert get_resp_header(preflight, "access-control-allow-origin") == [
               "http://localhost:6274"
             ]

      assert [headers] = get_resp_header(preflight, "access-control-allow-headers")
      assert headers =~ "mcp-protocol-version"

      denied =
        conn
        |> put_req_header("origin", "https://evil.example")
        |> get(~p"/.well-known/oauth-authorization-server")

      assert get_resp_header(denied, "access-control-allow-origin") == []
    end
  end

  describe "POST /oauth/register (RFC 7591)" do
    test "registers a public client and returns its metadata", %{conn: conn} do
      body =
        conn
        |> post(~p"/oauth/register", %{
          "client_name" => "Claude",
          "redirect_uris" => [OAuthFixtures.claude_callback()],
          "token_endpoint_auth_method" => "none",
          "grant_types" => ["authorization_code", "refresh_token"],
          "response_types" => ["code"],
          "application_type" => "web"
        })
        |> json_response(201)

      assert body["client_id"]
      refute Map.has_key?(body, "client_secret")
      assert body["client_name"] == "Claude"
      assert body["redirect_uris"] == [OAuthFixtures.claude_callback()]
      assert body["token_endpoint_auth_method"] == "none"
      assert is_integer(body["client_id_issued_at"])
    end

    test "a confidential registration returns the secret once", %{conn: conn} do
      body =
        conn
        |> post(~p"/oauth/register", %{"redirect_uris" => [OAuthFixtures.claude_callback()]})
        |> json_response(201)

      assert body["client_secret"]
      assert body["client_secret_expires_at"] == 0
      assert body["token_endpoint_auth_method"] == "client_secret_basic"
    end

    test "a redirect URI outside the allowlist is refused", %{conn: conn} do
      body =
        conn
        |> post(~p"/oauth/register", %{"redirect_uris" => ["https://evil.example/cb"]})
        |> json_response(400)

      assert body["error"] == "invalid_redirect_uri"
      assert body["error_description"] =~ "evil.example"
    end

    test "missing redirect URIs and bad metadata are refused", %{conn: conn} do
      assert %{"error" => "invalid_redirect_uri"} =
               conn |> post(~p"/oauth/register", %{"client_name" => "x"}) |> json_response(400)

      assert %{"error" => "invalid_client_metadata"} =
               conn
               |> post(~p"/oauth/register", %{
                 "redirect_uris" => [OAuthFixtures.claude_callback()],
                 "token_endpoint_auth_method" => "private_key_jwt"
               })
               |> json_response(400)
    end
  end

  describe "POST /oauth/token authorization_code" do
    setup do
      member = McEmcommFixtures.member_fixture()
      client = OAuthFixtures.public_client_fixture()
      {code, grant} = OAuthFixtures.authorization_code_fixture(member.user, client)
      %{user: member.user, client: client, code: code, grant: grant}
    end

    test "a public client redeems its code with PKCE and gets an audience-bound pair", ctx do
      body =
        ctx.conn
        |> post(~p"/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => ctx.code,
          "client_id" => ctx.client.client_id,
          "redirect_uri" => ctx.grant.redirect_uri,
          "code_verifier" => ctx.grant.code_verifier,
          "resource" => OAuth.resource_url()
        })
        |> json_response(200)

      assert body["token_type"] == "Bearer"
      assert body["expires_in"] == 900
      assert body["scope"] == "emcomm:member emcomm:operations"
      assert body["access_token"]
      assert body["refresh_token"]

      token = Repo.get_by!(Token, hashed_token: OAuth.hash(body["access_token"]))
      assert token.audience == OAuth.resource_url()
      assert token.user_id == ctx.user.id
    end

    test "the response forbids caching", ctx do
      conn = redeem(ctx)
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
    end

    test "a wrong verifier, a reused code, or an inexact redirect URI is invalid_grant", ctx do
      other = OAuthFixtures.pkce_fixture()

      assert %{"error" => "invalid_grant"} =
               redeem(ctx, %{"code_verifier" => other.verifier}) |> json_response(400)

      assert %{"error" => "invalid_grant"} =
               redeem(ctx, %{"redirect_uri" => ctx.grant.redirect_uri <> "/"})
               |> json_response(400)

      assert json_response(redeem(ctx), 200)
      assert %{"error" => "invalid_grant"} = json_response(redeem(ctx), 400)
    end

    test "an unknown client is 401 invalid_client so the client re-registers", ctx do
      conn = redeem(ctx, %{"client_id" => "vanished"})
      assert %{"error" => "invalid_client"} = json_response(conn, 401)
    end

    test "a confidential client must send its secret (post or basic)", ctx do
      {client, secret} = OAuthFixtures.confidential_client_fixture()
      {code, grant} = OAuthFixtures.authorization_code_fixture(ctx.user, client)

      params = %{
        "grant_type" => "authorization_code",
        "code" => code,
        "client_id" => client.client_id,
        "redirect_uri" => grant.redirect_uri,
        "code_verifier" => grant.code_verifier
      }

      assert %{"error" => "invalid_client"} =
               ctx.conn |> post(~p"/oauth/token", params) |> json_response(401)

      basic = Base.encode64("#{client.client_id}:#{secret}")

      assert %{"access_token" => _} =
               ctx.conn
               |> put_req_header("authorization", "Basic " <> basic)
               |> post(~p"/oauth/token", Map.delete(params, "client_id"))
               |> json_response(200)
    end

    test "the static client from configuration works with client_secret_post", ctx do
      {:ok, static} = McEmcomm.OAuth.Clients.fetch("static-test-client")
      {code, grant} = OAuthFixtures.authorization_code_fixture(ctx.user, static)

      body =
        ctx.conn
        |> post(~p"/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => code,
          "client_id" => "static-test-client",
          "client_secret" => "static-test-secret",
          "redirect_uri" => grant.redirect_uri,
          "code_verifier" => grant.code_verifier
        })
        |> json_response(200)

      assert body["access_token"]
    end

    test "unsupported and missing grant types are reported", ctx do
      assert %{"error" => "unsupported_grant_type"} =
               ctx.conn
               |> post(~p"/oauth/token", %{
                 "grant_type" => "password",
                 "client_id" => ctx.client.client_id
               })
               |> json_response(400)

      assert %{"error" => "invalid_request"} =
               ctx.conn
               |> post(~p"/oauth/token", %{"client_id" => ctx.client.client_id})
               |> json_response(400)
    end

    defp redeem(ctx, overrides \\ %{}) do
      params =
        Map.merge(
          %{
            "grant_type" => "authorization_code",
            "code" => ctx.code,
            "client_id" => ctx.client.client_id,
            "redirect_uri" => ctx.grant.redirect_uri,
            "code_verifier" => ctx.grant.code_verifier
          },
          Map.new(overrides)
        )

      post(ctx.conn, ~p"/oauth/token", params)
    end
  end

  describe "POST /oauth/token refresh_token and POST /oauth/revoke" do
    setup do
      member = McEmcommFixtures.member_fixture()
      client = OAuthFixtures.public_client_fixture()
      issued = OAuthFixtures.tokens_fixture(member.user, client_id: client.client_id)
      %{client: client, issued: issued}
    end

    test "refresh rotates and reuse revokes the family", %{
      conn: conn,
      client: client,
      issued: issued
    } do
      params = %{
        "grant_type" => "refresh_token",
        "refresh_token" => issued.refresh_token,
        "client_id" => client.client_id
      }

      next = conn |> post(~p"/oauth/token", params) |> json_response(200)
      refute next["refresh_token"] == issued.refresh_token

      assert %{"error" => "invalid_grant"} =
               conn |> post(~p"/oauth/token", params) |> json_response(400)

      assert %{"error" => "invalid_grant"} =
               conn
               |> post(~p"/oauth/token", %{params | "refresh_token" => next["refresh_token"]})
               |> json_response(400)
    end

    test "revocation kills the token and answers 200 regardless", %{
      conn: conn,
      client: client,
      issued: issued
    } do
      assert conn
             |> post(~p"/oauth/revoke", %{
               "token" => issued.refresh_token,
               "client_id" => client.client_id
             })
             |> json_response(200)

      assert McEmcomm.OAuth.Tokens.verify_access(issued.access_token, OAuth.resource_url()) ==
               {:error, :invalid_token}

      assert conn
             |> post(~p"/oauth/revoke", %{"token" => "unknown", "client_id" => client.client_id})
             |> json_response(200)

      assert %{"error" => "invalid_client"} =
               conn
               |> post(~p"/oauth/revoke", %{"token" => "x", "client_id" => "nobody"})
               |> json_response(401)
    end
  end
end

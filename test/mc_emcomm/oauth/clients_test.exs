defmodule McEmcomm.OAuth.ClientsTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.Client
  alias McEmcomm.OAuth.Clients
  alias McEmcomm.OAuthFixtures

  describe "register/1 (RFC 7591)" do
    test "a public client gets an id and no secret" do
      client = OAuthFixtures.public_client_fixture()
      assert byte_size(client.client_id) > 20
      assert is_nil(client.hashed_secret)
      assert {:ok, ^client} = Clients.fetch(client.client_id)
    end

    test "a confidential client's secret is returned once and stored hashed" do
      {client, secret} = OAuthFixtures.confidential_client_fixture()
      assert byte_size(secret) > 20
      assert client.hashed_secret == OAuth.hash(secret)
      refute Repo.get!(Client, client.id).hashed_secret == secret
      assert Clients.authenticate(client, secret) == :ok
      assert Clients.authenticate(client, "wrong") == {:error, :invalid_client}
      assert Clients.authenticate(client, nil) == {:error, :invalid_client}
    end

    test "a public client must not present a secret" do
      client = OAuthFixtures.public_client_fixture()
      assert Clients.authenticate(client, nil) == :ok
      assert Clients.authenticate(client, "anything") == {:error, :invalid_client}
    end

    test "only Claude's callbacks and loopback URIs may be registered" do
      assert {:error, changeset} =
               Clients.register(%{"redirect_uris" => ["https://evil.example/callback"]})

      assert %{redirect_uris: [message]} = errors_on(changeset)
      assert message =~ "https://evil.example/callback"

      assert {:ok, _client, _secret} =
               Clients.register(%{
                 "redirect_uris" => [
                   "https://claude.com/api/mcp/auth_callback",
                   "http://localhost:3118/callback",
                   OAuthFixtures.loopback_callback()
                 ]
               })
    end

    test "redirect URIs are required and unsupported grant types are refused" do
      assert {:error, changeset} = Clients.register(%{})
      assert %{redirect_uris: _} = errors_on(changeset)

      assert {:error, changeset} =
               Clients.register(%{
                 "redirect_uris" => [OAuthFixtures.claude_callback()],
                 "grant_types" => ["client_credentials"]
               })

      assert %{grant_types: _} = errors_on(changeset)
    end

    test "a client cannot choose its own client_id or secret" do
      {:ok, client, _} =
        Clients.register(%{
          "redirect_uris" => [OAuthFixtures.claude_callback()],
          "client_id" => "chosen",
          "client_secret" => "chosen"
        })

      refute client.client_id == "chosen"
    end
  end

  describe "redirect_uri_allowed?/2" do
    test "registered URIs match exactly" do
      client = OAuthFixtures.public_client_fixture()
      assert Clients.redirect_uri_allowed?(client, OAuthFixtures.claude_callback())
      refute Clients.redirect_uri_allowed?(client, OAuthFixtures.claude_callback() <> "/")
      refute Clients.redirect_uri_allowed?(client, "https://claude.ai/api/mcp/auth_callback?x=1")
    end

    test "a registered loopback URI matches on any port (RFC 8252 §7.3)" do
      client = OAuthFixtures.public_client_fixture()
      assert Clients.redirect_uri_allowed?(client, "http://localhost:3118/callback")
      assert Clients.redirect_uri_allowed?(client, "http://localhost/callback")
      refute Clients.redirect_uri_allowed?(client, "http://localhost:3118/other")
      refute Clients.redirect_uri_allowed?(client, "http://127.0.0.1:3118/callback")
    end
  end

  describe "the static client" do
    test "is resolved from configuration and authenticates with its secret" do
      assert {:ok, %Client{id: nil} = client} = Clients.fetch("static-test-client")
      assert Clients.authenticate(client, "static-test-secret") == :ok
      assert Clients.authenticate(client, "nope") == {:error, :invalid_client}
      assert Clients.redirect_uri_allowed?(client, OAuthFixtures.claude_callback())
      assert Clients.redirect_uri_allowed?(client, "http://127.0.0.1:9999/cb")
      refute Clients.redirect_uri_allowed?(client, "https://evil.example/cb")
    end

    test "unknown ids are not found" do
      assert Clients.fetch("nobody") == :error
      assert Clients.fetch(nil) == :error
    end
  end
end

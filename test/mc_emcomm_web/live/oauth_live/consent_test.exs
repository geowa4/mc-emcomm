defmodule McEmcommWeb.OAuthLive.ConsentTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.AuthorizationCodes
  alias McEmcomm.OAuthFixtures

  setup do
    client = OAuthFixtures.public_client_fixture(%{"client_name" => "Claude"})
    pkce = OAuthFixtures.pkce_fixture()
    %{client: client, pkce: pkce}
  end

  defp authorize_path(client, pkce, overrides \\ %{}) do
    params =
      Map.merge(
        %{
          "response_type" => "code",
          "client_id" => client.client_id,
          "redirect_uri" => OAuthFixtures.claude_callback(),
          "code_challenge" => pkce.challenge,
          "code_challenge_method" => "S256",
          "resource" => OAuth.resource_url(),
          "scope" => "emcomm:member emcomm:operations emcomm:membership",
          "state" => "xyz"
        },
        overrides
      )

    ~p"/oauth/authorize?#{params}"
  end

  test "an anonymous visitor is sent to log in and returned with the full query string", ctx do
    path = authorize_path(ctx.client, ctx.pkce)
    conn = get(ctx.conn, path)
    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) == path
  end

  test "an approved member sees the granted and withheld scopes and can approve", ctx do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(ctx.conn, member.user)
    {:ok, view, html} = live(conn, authorize_path(ctx.client, ctx.pkce))

    assert html =~ "Claude"
    assert has_element?(view, "#consent-granted", "emcomm:member")
    assert has_element?(view, "#consent-granted", "emcomm:operations")
    assert has_element?(view, "#consent-withheld", "emcomm:membership")
    assert has_element?(view, "#consent-redirect-host", "claude.ai")

    {:error, {:redirect, %{to: url}}} = view |> element("#consent-approve") |> render_click()
    uri = URI.parse(url)
    assert "#{uri.scheme}://#{uri.host}#{uri.path}" == OAuthFixtures.claude_callback()
    query = URI.decode_query(uri.query)
    assert query["state"] == "xyz"
    assert query["iss"] == OAuth.issuer()

    # The code is bound to exactly what the screen said, PKCE included.
    assert {:ok, code} =
             AuthorizationCodes.redeem(query["code"], %{
               client_id: ctx.client.client_id,
               redirect_uri: OAuthFixtures.claude_callback(),
               code_verifier: ctx.pkce.verifier,
               resource: OAuth.resource_url()
             })

    assert code.scopes == ["emcomm:member", "emcomm:operations"]
    assert code.user_id == member.user.id
  end

  test "an admin is granted every scope", ctx do
    scope = McEmcommFixtures.admin_scope_fixture()
    conn = log_in_user(ctx.conn, scope.user)
    {:ok, view, _html} = live(conn, authorize_path(ctx.client, ctx.pkce))
    assert has_element?(view, "#consent-granted", "emcomm:membership")
    refute has_element?(view, "#consent-withheld")
  end

  test "denying returns access_denied with the state", ctx do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(ctx.conn, member.user)
    {:ok, view, _html} = live(conn, authorize_path(ctx.client, ctx.pkce))

    {:error, {:redirect, %{to: url}}} = view |> element("#consent-deny") |> render_click()
    query = URI.decode_query(URI.parse(url).query)
    assert query["error"] == "access_denied"
    assert query["state"] == "xyz"
    assert McEmcomm.Repo.all(McEmcomm.OAuth.AuthorizationCode) == []
  end

  test "a pending member cannot approve anything", ctx do
    pending = McEmcommFixtures.pending_member_fixture()
    conn = log_in_user(ctx.conn, pending.user)
    {:ok, view, _html} = live(conn, authorize_path(ctx.client, ctx.pkce))
    assert has_element?(view, "#consent-no-access")
    refute has_element?(view, "#consent-approve")
    assert has_element?(view, "#consent-deny")
  end

  test "a loopback redirect shows the local-application warning", ctx do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(ctx.conn, member.user)

    path =
      authorize_path(ctx.client, ctx.pkce, %{"redirect_uri" => "http://localhost:3118/callback"})

    {:ok, view, html} = live(conn, path)
    assert has_element?(view, "#consent-redirect-host", "localhost")
    assert html =~ "running on this computer"
  end

  test "an unknown client or unregistered redirect URI is a dead end, never a redirect", ctx do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(ctx.conn, member.user)

    {:ok, view, _} = live(conn, authorize_path(ctx.client, ctx.pkce, %{"client_id" => "ghost"}))
    assert has_element?(view, "#consent-error", "not registered")
    refute has_element?(view, "#consent-approve")

    {:ok, view, _} =
      live(
        conn,
        authorize_path(ctx.client, ctx.pkce, %{"redirect_uri" => "https://evil.example/cb"})
      )

    assert has_element?(view, "#consent-error", "did not register")
  end

  test "plain PKCE, a foreign resource, a bad response type, and unknown scopes are redirected as errors",
       ctx do
    member = McEmcommFixtures.member_fixture()
    conn = log_in_user(ctx.conn, member.user)

    cases = [
      {%{"code_challenge_method" => "plain"}, "invalid_request"},
      {%{"code_challenge" => nil}, "invalid_request"},
      {%{"resource" => "https://other.example/mcp"}, "invalid_target"},
      {%{"response_type" => "token"}, "unsupported_response_type"},
      {%{"scope" => "emcomm:member openid"}, "invalid_scope"}
    ]

    for {overrides, expected} <- cases do
      path = authorize_path(ctx.client, ctx.pkce, overrides)
      assert {:error, {:redirect, %{to: url}}} = live(conn, path)
      query = URI.decode_query(URI.parse(url).query)
      assert query["error"] == expected, "#{inspect(overrides)} -> #{inspect(query)}"
      assert query["state"] == "xyz"
      assert query["iss"] == OAuth.issuer()
    end
  end
end

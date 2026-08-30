defmodule McEmcommWeb.LiveSessionAuthTest do
  @moduledoc """
  One authorization test per live_session gate (spec §18): `:public` is open
  to everyone; `:member` requires an approved member (or an admin); `:admin`
  requires `is_admin`.
  """

  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.McEmcommFixtures

  describe ":public live_session" do
    test "is reachable without logging in" do
      conn = build_conn()
      assert {:ok, _view, html} = live(conn, ~p"/about")
      assert html =~ "About"
    end
  end

  describe ":member live_session (McEmcommWeb.MemberAuth :require_member)" do
    test "redirects an anonymous visitor to log in" do
      conn = build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/app")
    end

    test "redirects a logged-in user with no member profile" do
      user = McEmcomm.AccountsFixtures.user_fixture()
      conn = log_in_user(build_conn(), user)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/app")
    end

    test "redirects a pending (not yet approved) member" do
      member = McEmcommFixtures.pending_member_fixture()
      conn = log_in_user(build_conn(), member.user)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/app")
    end

    test "allows an approved member" do
      member = McEmcommFixtures.member_fixture()
      conn = log_in_user(build_conn(), member.user)
      assert {:ok, _view, html} = live(conn, ~p"/app")
      assert html =~ "Member Portal"
    end

    test "allows an admin even without an approved member profile" do
      scope = McEmcommFixtures.admin_scope_fixture()
      conn = log_in_user(build_conn(), scope.user)
      assert {:ok, _view, _html} = live(conn, ~p"/app")
    end
  end

  describe ":admin live_session (McEmcommWeb.MemberAuth :require_admin)" do
    test "redirects an anonymous visitor to log in" do
      conn = build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin")
    end

    test "redirects an approved member who is not an admin" do
      member = McEmcommFixtures.member_fixture()
      conn = log_in_user(build_conn(), member.user)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
    end

    test "allows an admin" do
      scope = McEmcommFixtures.admin_scope_fixture()
      conn = log_in_user(build_conn(), scope.user)
      assert {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Admin"
    end
  end
end

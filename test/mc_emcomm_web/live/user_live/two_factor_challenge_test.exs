defmodule McEmcommWeb.UserLive.TwoFactorChallengeTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import McEmcomm.AccountsFixtures

  setup do
    user_with_totp_fixture()
  end

  describe "challenge page" do
    test "renders the authenticator code form for a pending login", %{conn: conn, user: user} do
      {:ok, lv, _html} = conn |> put_pending_two_factor(user) |> live(~p"/users/two-factor")

      assert has_element?(lv, "#two_factor_form")
      assert has_element?(lv, "#user_code[inputmode=numeric][pattern]")
      assert has_element?(lv, "#two-factor-use-recovery")
      refute has_element?(lv, "#two-factor-use-totp")
    end

    test "switches between recovery code and authenticator input", %{conn: conn, user: user} do
      {:ok, lv, _html} = conn |> put_pending_two_factor(user) |> live(~p"/users/two-factor")

      lv |> element("#two-factor-use-recovery") |> render_click()
      assert has_element?(lv, "#user_code")
      refute has_element?(lv, "#user_code[pattern]")
      assert has_element?(lv, "#two-factor-use-totp")

      lv |> element("#two-factor-use-totp") |> render_click()
      assert has_element?(lv, "#user_code[pattern]")
    end

    test "redirects to login when nothing is pending", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/users/two-factor")

      assert path == ~p"/users/log-in"
      assert %{"error" => "Your login has expired. Please log in again."} = flash
    end

    test "redirects to login when the pending login expired", %{conn: conn, user: user} do
      assert {:error, {:live_redirect, %{to: path}}} =
               conn
               |> put_pending_two_factor(user, at: System.os_time(:second) - 601)
               |> live(~p"/users/two-factor")

      assert path == ~p"/users/log-in"
    end
  end

  describe "submitting a code" do
    test "a valid code completes the login", %{conn: conn, user: user, secret: secret} do
      conn = put_pending_two_factor(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/two-factor")

      form = form(lv, "#two_factor_form", user: %{code: totp_code(secret)})
      render_submit(form)

      conn = follow_trigger_action(form, conn)
      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert_logged_in_menu(conn, user)
    end

    test "an invalid code returns to the challenge with an error", %{conn: conn, user: user} do
      conn = put_pending_two_factor(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/two-factor")

      form = form(lv, "#two_factor_form", user: %{code: "000000"})
      render_submit(form)

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid code."
      assert redirected_to(conn) == ~p"/users/two-factor"
      refute get_session(conn, :user_token)
    end
  end
end

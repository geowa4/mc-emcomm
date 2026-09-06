defmodule McEmcommWeb.UserLive.MailFailureTest do
  # Swaps the global mailer config, so it cannot share the VM with other tests.
  use McEmcommWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import McEmcomm.AccountsFixtures

  alias McEmcomm.Accounts

  # The fixture confirms the user through the mailer, so it must run before
  # the adapter is swapped for the failing one.
  setup do
    %{user: user_fixture()}
  end

  setup do
    original = Application.get_env(:mc_emcomm, McEmcomm.Mailer)

    Application.put_env(
      :mc_emcomm,
      McEmcomm.Mailer,
      Keyword.put(original, :adapter, McEmcomm.FailingMailAdapter)
    )

    on_exit(fn -> Application.put_env(:mc_emcomm, McEmcomm.Mailer, original) end)
    :ok
  end

  describe "registration" do
    test "keeps the account and explains how to get a link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      log =
        capture_log(fn ->
          {:ok, _lv, html} = form |> render_submit() |> follow_redirect(conn, ~p"/users/log-in")

          assert html =~ "confirmation email could not be sent"
          refute html =~ "An email was sent"
        end)

      assert Accounts.get_user_by_email(email)
      assert log =~ "Could not deliver confirmation instructions"
      assert log =~ "API key is invalid"
    end
  end

  describe "magic link login" do
    test "keeps the neutral flash and logs the failure", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      log =
        capture_log(fn ->
          {:ok, _lv, html} =
            form(lv, "#login_form_magic", user: %{email: user.email})
            |> render_submit()
            |> follow_redirect(conn, ~p"/users/log-in")

          assert html =~ "If your email is in our system"
          refute html =~ "could not be sent"
        end)

      assert log =~ "Could not deliver login instructions"
    end
  end

  describe "email change" do
    test "reports the failure and leaves the email unchanged", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      log =
        capture_log(fn ->
          result =
            lv
            |> form("#email_form", %{"user" => %{"email" => unique_user_email()}})
            |> render_submit()

          assert result =~ "confirmation email could not be sent"
          refute result =~ "A link to confirm your email"
        end)

      assert Accounts.get_user_by_email(user.email)
      assert log =~ "Could not deliver email change instructions"
    end
  end
end

defmodule McEmcommWeb.UserLive.SettingsEmailsTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import McEmcomm.AccountsFixtures
  import Swoosh.TestAssertions

  alias McEmcomm.Accounts

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  # The fixtures mail confirmation links of their own; drop them so the
  # assertions below see only what the page sent.
  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  describe "additional email addresses" do
    test "shows the primary address and an empty state", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#additional-emails #primary-email", user.email)
      assert has_element?(lv, "#user-emails-empty")
      assert has_element?(lv, "#add_email_form")
    end

    test "lists the user's additional addresses", %{conn: conn, user: user} do
      extra = user_email_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert has_element?(lv, "#user_emails-#{extra.id}", extra.email)
      assert has_element?(lv, "#make-primary-#{extra.id}")
      assert has_element?(lv, "#remove-email-#{extra.id}")
    end

    test "mails a confirmation link to a new address", %{conn: conn, user: user} do
      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      flush_emails()

      lv
      |> form("#add_email_form", %{"user_email" => %{"email" => email}})
      |> render_submit()

      assert has_element?(lv, "#flash-info", "A confirmation link has been sent to #{email}.")
      assert_email_sent(to: email, subject: "Confirm your additional email address")
      assert Accounts.list_user_emails(user) == []
    end

    test "answers the same way for an address another account holds", %{conn: conn} do
      other = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      flush_emails()

      lv
      |> form("#add_email_form", %{"user_email" => %{"email" => other.email}})
      |> render_submit()

      assert has_element?(
               lv,
               "#flash-info",
               "A confirmation link has been sent to #{other.email}."
             )

      assert_email_sent(
        to: other.email,
        subject: "Another account is trying to claim this email address"
      )
    end

    test "rejects a malformed address and the user's own", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      flush_emails()

      assert lv
             |> form("#add_email_form", %{"user_email" => %{"email" => "with spaces"}})
             |> render_change() =~ "must have the @ sign and no spaces"

      assert lv
             |> form("#add_email_form", %{"user_email" => %{"email" => user.email}})
             |> render_submit() =~ "is already one of your addresses"

      assert_no_email_sent()
    end

    test "removes an address", %{conn: conn, user: user} do
      extra = user_email_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      lv |> element("#remove-email-#{extra.id}") |> render_click()

      refute has_element?(lv, "#user_emails-#{extra.id}")
      assert has_element?(lv, "#flash-info", "was removed from your account")
      assert Accounts.list_user_emails(user) == []
    end

    test "makes an address the primary one", %{conn: conn, user: user} do
      extra = user_email_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      lv |> element("#make-primary-#{extra.id}") |> render_click()
      assert_redirect(lv, ~p"/users/settings")

      assert Accounts.get_user!(user.id).email == extra.email
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      assert has_element?(lv, "#primary-email", extra.email)
      assert has_element?(lv, "#user-emails", user.email)
    end

    test "declines ids the page never offered", %{conn: conn} do
      theirs = user_email_fixture(user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      for {event, id} <- [
            {"remove_email", theirs.id},
            {"remove_email", "junk"},
            {"make_primary", theirs.id},
            {"make_primary", "junk"}
          ] do
        render_click(lv, event, %{"id" => id})
        assert has_element?(lv, "#flash-error", "could not be")
      end

      assert Accounts.get_user_by_email(theirs.email).id == theirs.user_id
    end
  end

  describe "logging in with an additional address" do
    test "the magic link form mails the address that was typed", %{conn: conn, user: user} do
      extra = user_email_fixture(user)
      {:ok, lv, _html} = build_conn() |> live(~p"/users/log-in")
      flush_emails()

      {:ok, _lv, html} =
        lv
        |> form("#login_form_magic", user: %{email: extra.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"
      assert_email_sent(to: extra.email, subject: "Log in instructions")
    end

    test "the password form accepts it", %{user: user} do
      user = set_password(user)
      extra = user_email_fixture(user)

      conn =
        post(build_conn(), ~p"/users/log-in", %{
          "user" => %{"email" => extra.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end
  end
end

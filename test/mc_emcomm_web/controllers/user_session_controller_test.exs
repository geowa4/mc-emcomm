defmodule McEmcommWeb.UserSessionControllerTest do
  use McEmcommWeb.ConnCase, async: true

  import McEmcomm.AccountsFixtures
  alias McEmcomm.Accounts
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      assert_logged_in_menu(conn, user)
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_mc_emcomm_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      assert_logged_in_menu(conn, user)
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."

      assert Accounts.get_user!(user.id).confirmed_at

      assert_logged_in_menu(conn, user)
    end

    test "confirming a new member emails the flagged position holders", %{
      conn: conn,
      unconfirmed_user: user
    } do
      holder = McEmcommFixtures.member_fixture()
      flagged = McEmcommFixtures.position_fixture(%{notify_on_new_member: true})
      {:ok, _} = Members.assign_position(holder, flagged)
      {:ok, _member} = Members.create_member(%{user_id: user.id, name: "Newcomer"})
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)

      holder_email = holder.user.email

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "New member awaiting approval: Newcomer",
                        to: [{_, ^holder_email}]
                      }}
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - two-factor gate" do
    test "parks a password login when TOTP is enabled", %{conn: conn} do
      %{user: user} = user_with_totp_fixture()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/users/two-factor"
      refute get_session(conn, :user_token)
      refute conn.resp_cookies["_mc_emcomm_web_user_remember_me"]

      pending = get_session(conn, :pending_two_factor)
      assert pending["user_id"] == user.id
      assert pending["remember_me"] == "true"
      assert pending["info"] == "Welcome back!"
    end

    test "parks a magic link login when TOTP is enabled", %{conn: conn} do
      %{user: user} = user_with_totp_fixture()
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert redirected_to(conn) == ~p"/users/two-factor"
      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_two_factor)["user_id"] == user.id

      # the magic link was consumed by the primary factor
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "POST /users/two-factor" do
    setup do
      user_with_totp_fixture()
    end

    test "logs the user in with a valid authenticator code", %{
      conn: conn,
      user: user,
      secret: secret
    } do
      conn =
        conn
        |> put_pending_two_factor(user)
        |> post(~p"/users/two-factor", %{"user" => %{"code" => totp_code(secret)}})

      assert get_session(conn, :user_token)
      refute get_session(conn, :pending_two_factor)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Welcome back!"

      assert_logged_in_menu(conn, user)
    end

    test "honors remember me and return to from the parked login", %{
      conn: conn,
      user: user,
      secret: secret
    } do
      conn =
        conn
        |> put_pending_two_factor(user, remember_me: "true")
        |> put_session(:user_return_to, "/foo/bar")
        |> post(~p"/users/two-factor", %{"user" => %{"code" => totp_code(secret)}})

      assert conn.resp_cookies["_mc_emcomm_web_user_remember_me"]
      assert redirected_to(conn) == "/foo/bar"
    end

    test "logs the user in with a recovery code and reports the remainder", %{
      conn: conn,
      user: user,
      recovery_codes: [code | _]
    } do
      conn =
        conn
        |> put_pending_two_factor(user)
        |> post(~p"/users/two-factor", %{"user" => %{"code" => code}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "recovery code; 7 remaining"
      assert {:error, :invalid_code} = Accounts.verify_recovery_code(user, code)
    end

    test "sends an invalid code back to the challenge", %{conn: conn, user: user} do
      conn =
        conn
        |> put_pending_two_factor(user)
        |> post(~p"/users/two-factor", %{"user" => %{"code" => "000000"}})

      assert redirected_to(conn) == ~p"/users/two-factor"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid code."
      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_two_factor)["attempts"] == 1
    end

    test "discards the login after too many invalid codes", %{conn: conn, user: user} do
      conn =
        conn
        |> put_pending_two_factor(user, attempts: 4)
        |> post(~p"/users/two-factor", %{"user" => %{"code" => "000000"}})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many invalid codes"
      refute get_session(conn, :pending_two_factor)
      refute get_session(conn, :user_token)
    end

    test "rejects a code when nothing is pending or the login expired", %{
      conn: conn,
      user: user,
      secret: secret
    } do
      conn = post(conn, ~p"/users/two-factor", %{"user" => %{"code" => totp_code(secret)}})
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Your login has expired"
      refute get_session(conn, :user_token)

      conn =
        build_conn()
        |> put_pending_two_factor(user, at: System.os_time(:second) - 601)
        |> post(~p"/users/two-factor", %{"user" => %{"code" => totp_code(secret)}})

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end
  end

  describe "POST /users/update-password" do
    test "does not challenge a user with TOTP enabled", %{conn: conn} do
      %{user: user} = user_with_totp_fixture()
      new_password = "another valid password"

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert get_session(conn, :user_token)
      refute get_session(conn, :pending_two_factor)
      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end

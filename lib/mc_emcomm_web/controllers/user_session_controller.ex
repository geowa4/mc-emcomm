defmodule McEmcommWeb.UserSessionController do
  use McEmcommWeb, :controller

  alias McEmcomm.Accounts
  alias McEmcommWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.", :require_two_factor)
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!", :require_two_factor)
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info, mode) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)
        complete_login(conn, user, user_params, info, mode)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info, mode) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      complete_login(conn, user, user_params, info, mode)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  # The primary factor succeeded. Users with TOTP enabled are parked in the
  # session and sent to the challenge page; everyone else is logged in now.
  defp complete_login(conn, user, user_params, info, :require_two_factor) do
    if Accounts.totp_enabled?(user) do
      UserAuth.challenge_two_factor(conn, user, user_params, info)
    else
      complete_login(conn, user, user_params, info, :skip_two_factor)
    end
  end

  defp complete_login(conn, user, user_params, info, :skip_two_factor) do
    conn
    |> put_flash(:info, info)
    |> UserAuth.log_in_user(user, user_params)
  end

  @doc """
  Finishes a login parked by `McEmcommWeb.UserAuth.challenge_two_factor/4`.

  This is the only place a second factor is verified and a session minted:
  the challenge LiveView just posts the code here, because it cannot set
  cookies itself.
  """
  def verify_two_factor(conn, %{"user" => %{"code" => code}}) when is_binary(code) do
    case UserAuth.fetch_pending_two_factor(conn) do
      {:ok, pending} ->
        pending
        |> Map.fetch!("user_id")
        |> Accounts.get_user!()
        |> verify_pending(conn, pending, code)

      :error ->
        expired_challenge(conn)
    end
  end

  def verify_two_factor(conn, _params), do: expired_challenge(conn)

  defp verify_pending(user, conn, pending, code) do
    case Accounts.verify_two_factor(user, code) do
      {:ok, :totp} ->
        finish_challenge(conn, user, pending, pending["info"])

      {:ok, :recovery_code} ->
        remaining = Accounts.count_unused_recovery_codes(user)
        info = "#{pending["info"]} You used a recovery code; #{remaining} remaining."
        finish_challenge(conn, user, pending, info)

      {:error, :invalid_code} ->
        case UserAuth.fail_pending_two_factor(conn) do
          {:retry, conn} ->
            conn
            |> put_flash(:error, "Invalid code.")
            |> redirect(to: ~p"/users/two-factor")

          {:locked, conn} ->
            conn
            |> put_flash(:error, "Too many invalid codes. Please log in again.")
            |> redirect(to: ~p"/users/log-in")
        end
    end
  end

  defp finish_challenge(conn, user, pending, info) do
    conn
    |> UserAuth.clear_pending_two_factor()
    |> put_flash(:info, info)
    |> UserAuth.log_in_user(user, %{"remember_me" => pending["remember_me"]})
  end

  defp expired_challenge(conn) do
    conn
    |> put_flash(:error, "Your login has expired. Please log in again.")
    |> redirect(to: ~p"/users/log-in")
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    # The user is already authenticated and in sudo mode, so the re-login
    # that carries the new session must not be challenged again.
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!", :skip_two_factor)
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end

defmodule McEmcomm.Accounts.UserNotifier do
  @moduledoc """
  Delivers account emails (magic links, confirmation, email change,
  additional addresses, account merges) through `McEmcomm.Mailer`.
  """
  import Swoosh.Email

  alias McEmcomm.Accounts.User
  alias McEmcomm.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Monroe County ARES/RACES", Application.fetch_env!(:mc_emcomm, :mail_from)})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to confirm an additional email address, sent to that
  address.
  """
  def deliver_additional_email_instructions(user, address, url) do
    deliver(address, "Confirm your additional email address", """

    ==============================

    Hi #{address},

    The Monroe County ARES/RACES account #{user.email} asked to add this
    email address. You can confirm it by visiting the URL below while
    logged in to that account:

    #{url}

    If you didn't request this, please ignore this.

    ==============================
    """)
  end

  @doc """
  Tells the holder of an address that another account is claiming it, and
  that following the link merges the two accounts. Sent to that address.
  """
  def deliver_merge_instructions(user, address, url) do
    deliver(address, "Another account is trying to claim this email address", """

    ==============================

    Hi #{address},

    Another user, #{user.email}, is trying to claim this email address for
    their Monroe County ARES/RACES account. This address already belongs to
    an account.

    If both accounts are yours, you can merge them by visiting the URL below
    while logged in as #{user.email}:

    #{url}

    You will review which profile details to bring over from the account
    that uses this address. Once the merge is done that account is
    deactivated: its email addresses, training records, and history move to
    #{user.email}, and it can no longer be used to log in.

    If you didn't request this, please ignore this. Nothing changes unless
    the link is followed from the other account.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link, to `address` (one of
  the user's addresses; the primary one by default).
  """
  def deliver_login_instructions(user, url, address \\ nil) do
    address = address || user.email

    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(address, url)
    end
  end

  defp deliver_magic_link_instructions(address, url) do
    deliver(address, "Log in instructions", """

    ==============================

    Hi #{address},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end

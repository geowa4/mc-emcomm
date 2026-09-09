defmodule McEmcomm.Members.MemberNotifier do
  @moduledoc """
  Delivers membership emails (new-member notices to designated position
  holders, approval notices to the member) through `McEmcomm.Mailer`.

  This module is called from inside the `McEmcomm.Accounts` context, where no
  web caller can hand in a URL builder, so it resolves the admin link itself
  through verified routes.
  """
  use McEmcommWeb, :verified_routes

  import Swoosh.Email

  alias McEmcomm.Accounts.User
  alias McEmcomm.Mailer
  alias McEmcomm.Members.Member

  @doc """
  Sends one plain-text "new member awaiting approval" email to each recipient
  about `member` (whose account is `user`). Recipients each get their own
  message so holders' addresses are not exposed to one another.
  """
  @spec deliver_new_member_notice(Member.t(), User.t(), [User.t()]) ::
          {:ok, [Swoosh.Email.t()]} | {:error, term()}
  def deliver_new_member_notice(%Member{} = member, %User{} = user, recipients) do
    subject = "New member awaiting approval: #{member.name}"
    body = new_member_body(member, user)

    Enum.reduce_while(recipients, {:ok, []}, fn recipient, {:ok, sent} ->
      case deliver(recipient.email, subject, body) do
        {:ok, email} -> {:cont, {:ok, [email | sent]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sent} -> {:ok, Enum.reverse(sent)}
      error -> error
    end
  end

  @doc """
  Tells `user` that the membership profile `member` has been approved and
  where to log in.
  """
  @spec deliver_membership_approved(Member.t(), User.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_membership_approved(%Member{} = member, %User{} = user) do
    deliver(user.email, "Your Monroe County ARES/RACES membership is approved", """

    ==============================

    Hi #{member.name},

    Your membership in Monroe County ARES/RACES has been approved. Welcome
    aboard.

    Log in to the member portal to complete your profile, see upcoming
    operations, and check into nets:

    #{url(~p"/users/log-in")}

    ==============================
    """)
  end

  defp new_member_body(member, user) do
    """

    ==============================

    A new member has registered and is waiting for approval. They have not
    confirmed their email address yet.

    Name:      #{member.name}
    Call sign: #{member.call_sign || "none given"}
    Email:     #{user.email}

    Review pending members here:

    #{url(~p"/admin/members")}

    You are receiving this because you hold a leadership position configured
    to be notified when a new member joins.

    ==============================
    """
  end

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
end

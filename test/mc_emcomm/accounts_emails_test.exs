defmodule McEmcomm.AccountsEmailsTest do
  use McEmcomm.DataCase, async: true

  import McEmcomm.AccountsFixtures

  alias McEmcomm.Accounts
  alias McEmcomm.Accounts.{User, UserEmail, UserToken}
  alias McEmcomm.Members

  setup do
    %{user: user_fixture()}
  end

  describe "change_user_additional_email/2" do
    test "accepts a well-formed address, trimmed", %{user: user} do
      changeset = Accounts.change_user_additional_email(user, %{email: " second@example.com "})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :email) == "second@example.com"
    end

    test "rejects a malformed or oversized address", %{user: user} do
      assert %{email: ["must have the @ sign and no spaces"]} =
               errors_on(Accounts.change_user_additional_email(user, %{email: "not valid"}))

      too_long = String.duplicate("a", 160) <> "@example.com"

      assert %{email: ["should be at most 160 character(s)"]} =
               errors_on(Accounts.change_user_additional_email(user, %{email: too_long}))
    end

    test "rejects the user's own addresses, whatever the case", %{user: user} do
      extra = user_email_fixture(user)

      for address <- [user.email, String.upcase(user.email), String.upcase(extra.email)] do
        assert %{email: ["is already one of your addresses"]} =
                 errors_on(Accounts.change_user_additional_email(user, %{email: address}))
      end
    end

    test "does not reveal that an address belongs to somebody else", %{user: user} do
      other = user_fixture()
      assert Accounts.change_user_additional_email(user, %{email: other.email}).valid?
    end
  end

  describe "deliver_additional_email_instructions/3" do
    test "mails a confirmation link to a free address", %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          {:ok, message} = Accounts.deliver_additional_email_instructions(user, email, url)

          assert message.to == [{"", email}]
          assert message.subject == "Confirm your additional email address"
          assert message.text_body =~ user.email
          {:ok, message}
        end)

      {:ok, decoded} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, decoded))
      assert user_token.user_id == user.id
      assert user_token.sent_to == email
      assert user_token.context == "add_email"
    end

    test "warns the holder when the address belongs to another account", %{user: user} do
      other = user_fixture()

      {:ok, message} =
        Accounts.deliver_additional_email_instructions(user, other.email, &"[TOKEN]#{&1}[TOKEN]")

      assert message.to == [{"", other.email}]
      assert message.subject == "Another account is trying to claim this email address"
      assert message.text_body =~ "Another user, #{user.email}, is trying to claim"
      assert message.text_body =~ "merge"
      assert message.text_body =~ "deactivated"
    end

    test "warns the holder when the address is another account's additional one", %{user: user} do
      extra = user_email_fixture(user_fixture())

      {:ok, message} =
        Accounts.deliver_additional_email_instructions(user, extra.email, &"[TOKEN]#{&1}[TOKEN]")

      assert message.subject == "Another account is trying to claim this email address"
    end
  end

  describe "confirm_additional_email/2" do
    test "adds a free address and spends the token", %{user: user} do
      email = unique_user_email()
      token = email_claim_token(user, email)

      assert {:ok, %UserEmail{email: ^email}} = Accounts.confirm_additional_email(user, token)
      assert [%UserEmail{email: ^email}] = Accounts.list_user_emails(user)
      assert {:error, :invalid} = Accounts.confirm_additional_email(user, token)
      refute Repo.get_by(UserToken, user_id: user.id, context: "add_email")
    end

    test "asks for a merge when another account holds the address", %{user: user} do
      %{id: other_id} = other = user_fixture()
      token = email_claim_token(user, other.email)

      assert {:merge, %User{id: ^other_id}} = Accounts.confirm_additional_email(user, token)
      assert Accounts.list_user_emails(user) == []
      # The token is kept for the merge itself.
      assert {:merge, %User{}} = Accounts.confirm_additional_email(user, token)
    end

    test "refuses a token from another user's session", %{user: user} do
      token = email_claim_token(user, unique_user_email())
      intruder = user_fixture()

      assert {:error, :invalid} = Accounts.confirm_additional_email(intruder, token)
      assert Accounts.list_user_emails(intruder) == []
      assert Accounts.list_user_emails(user) == []
    end

    test "refuses a malformed, unknown, or expired token", %{user: user} do
      assert {:error, :invalid} = Accounts.confirm_additional_email(user, "not base64!")
      assert {:error, :invalid} = Accounts.confirm_additional_email(user, "dW5rbm93bg")

      token = email_claim_token(user, unique_user_email())

      Repo.update_all(from(t in UserToken, where: t.context == "add_email"),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -25, :hour)]
      )

      assert {:error, :invalid} = Accounts.confirm_additional_email(user, token)
    end

    test "refuses a link for an address the user has since gained", %{user: user} do
      email = unique_user_email()
      stale = email_claim_token(user, email)
      user_email_fixture(user, email)

      assert {:error, :invalid} = Accounts.confirm_additional_email(user, stale)
    end
  end

  describe "taken addresses" do
    test "an additional address cannot be registered or invited", %{user: user} do
      extra = user_email_fixture(user)

      assert {:error, changeset} = Accounts.register_user(%{email: String.upcase(extra.email)})
      assert %{email: ["has already been taken"]} = errors_on(changeset)

      {:ok, admin} = Accounts.promote_to_admin(user_fixture())

      assert {:error, invitation} =
               Members.invite_member(%{email: extra.email, name: "Somebody"}, admin)

      assert %{email: ["has already been taken"]} = errors_on(invitation)
    end

    test "an additional address cannot become another user's primary", %{user: user} do
      extra = user_email_fixture(user)

      changeset = Accounts.change_user_email(user_fixture(), %{email: extra.email})
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "logging in with an additional address" do
    setup %{user: user} do
      %{user: set_password(user), extra: user_email_fixture(user)}
    end

    test "get_user_by_email/1 finds the user, case-insensitively", %{user: user, extra: extra} do
      assert %User{id: id} = Accounts.get_user_by_email(String.upcase(extra.email))
      assert id == user.id
    end

    test "the password works with either address", %{user: user, extra: extra} do
      for address <- [user.email, extra.email] do
        assert %User{id: id} =
                 Accounts.get_user_by_email_and_password(address, valid_user_password())

        assert id == user.id
      end
    end

    test "the magic link is mailed to the address asked for", %{user: user, extra: extra} do
      token =
        extract_user_token(fn url ->
          {:ok, message} =
            Accounts.deliver_login_instructions(user, url, to: String.upcase(extra.email))

          assert message.to == [{"", extra.email}]
          {:ok, message}
        end)

      assert {:ok, {%User{id: id}, []}} = Accounts.login_user_by_magic_link(token)
      assert id == user.id
    end

    test "a link sent to a removed address stops working", %{user: user, extra: extra} do
      token =
        extract_user_token(&Accounts.deliver_login_instructions(user, &1, to: extra.email))

      {:ok, _} = Accounts.remove_user_email(user, extra.id)

      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
      refute Accounts.get_user_by_email(extra.email)
    end

    test "an address that is not the user's falls back to the primary", %{user: user} do
      {:ok, message} =
        Accounts.deliver_login_instructions(user, &"[TOKEN]#{&1}[TOKEN]",
          to: "stranger@example.com"
        )

      assert message.to == [{"", user.email}]
    end
  end

  describe "remove_user_email/2" do
    test "removes the user's address only", %{user: user} do
      extra = user_email_fixture(user)
      intruder = user_fixture()

      assert {:error, :not_found} = Accounts.remove_user_email(intruder, extra.id)
      assert {:error, :not_found} = Accounts.remove_user_email(user, nil)
      assert {:ok, %UserEmail{}} = Accounts.remove_user_email(user, extra.id)
      assert Accounts.list_user_emails(user) == []
    end
  end

  describe "make_email_primary/2" do
    test "swaps the primary address with the additional one", %{user: user} do
      extra = user_email_fixture(user)

      assert {:ok, %User{} = updated} = Accounts.make_email_primary(user, extra.id)
      assert updated.email == extra.email
      assert [%UserEmail{email: old}] = Accounts.list_user_emails(updated)
      assert old == user.email
      assert Accounts.get_user_by_email(user.email).id == user.id
    end

    test "refuses somebody else's address", %{user: user} do
      extra = user_email_fixture(user)

      assert {:error, :not_found} = Accounts.make_email_primary(user_fixture(), extra.id)
      assert {:error, :not_found} = Accounts.make_email_primary(user, nil)
      assert Accounts.get_user!(user.id).email == user.email
    end
  end
end

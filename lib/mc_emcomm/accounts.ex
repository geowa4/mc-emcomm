defmodule McEmcomm.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias McEmcomm.Repo

  alias McEmcomm.Accounts.{RecoveryCode, User, UserEmail, UserNotifier, UserToken}

  @totp_issuer "Monroe County ARES/RACES"
  @totp_code_format ~r/^\d{6}$/

  ## Database getters

  @doc """
  Gets a user by any of their email addresses, primary or additional.
  Deactivated accounts are never returned.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.one(
      from u in User,
        left_join: e in UserEmail,
        on: e.user_id == u.id and e.email == ^email,
        where: is_nil(u.deactivated_at),
        where: u.email == ^email or not is_nil(e.id)
    )
  end

  @doc """
  Gets a user by email and password. Any of the user's addresses works.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(integer() | String.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Administration

  @doc """
  Grants the admin flag to a user.

  Idempotent: promoting an existing admin returns `{:ok, user}` unchanged.
  Admin status is independent of membership; see `McEmcomm.Accounts.Scope.admin?/1`.

  ## Examples

      iex> promote_to_admin(user)
      {:ok, %User{is_admin: true}}

  """
  @spec promote_to_admin(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def promote_to_admin(%User{} = user) do
    user
    |> User.admin_changeset()
    |> Repo.update()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  @spec sudo_mode?(User.t() | nil, integer()) :: boolean()
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `McEmcomm.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_email(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  @spec update_user_email(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, :transaction_aborted}
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  ## Additional email addresses

  @doc """
  Lists the user's additional (verified) addresses, oldest first. The
  primary address is `user.email` and is not part of this list.
  """
  @spec list_user_emails(User.t()) :: [UserEmail.t()]
  def list_user_emails(%User{id: user_id}) do
    Repo.all(from e in UserEmail, where: e.user_id == ^user_id, order_by: [asc: e.id])
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for an address the user wants to add.

  An address the user already has is refused. One that belongs to somebody
  else is not: claiming it starts an account merge (`McEmcomm.AccountMerge`).
  """
  @spec change_user_additional_email(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_additional_email(%User{} = user, attrs \\ %{}) do
    %UserEmail{user_id: user.id}
    |> UserEmail.changeset(attrs)
    |> Ecto.Changeset.validate_change(:email, fn :email, email ->
      if own_address(user, email),
        do: [email: "is already one of your addresses"],
        else: []
    end)
  end

  @doc ~S"""
  Emails a confirmation link to an address the user wants to add, proving
  they can read mail sent there. `email` must have passed
  `change_user_additional_email/2`.

  When the address already belongs to another account the message says so,
  and that following the link merges the two accounts. The caller cannot
  tell the two cases apart, so the form answers identically for both.

  ## Examples

      iex> deliver_additional_email_instructions(user, email, &url(~p"/users/settings/emails/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_additional_email_instructions(User.t(), String.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_additional_email_instructions(%User{} = user, email, confirm_url_fun)
      when is_binary(email) and is_function(confirm_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "add_email", email)
    Repo.insert!(user_token)
    url = confirm_url_fun.(encoded_token)

    case get_user_by_email(email) do
      nil -> UserNotifier.deliver_additional_email_instructions(user, email, url)
      %User{} -> UserNotifier.deliver_merge_instructions(user, email, url)
    end
  end

  @doc """
  Looks up the add-email token the user was sent. The token must be the
  logged-in user's own: a link opened from somebody else's session proves
  nothing about them.
  """
  @spec fetch_email_claim(User.t(), String.t()) :: {:ok, UserToken.t()} | {:error, :invalid}
  def fetch_email_claim(%User{id: user_id}, token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_add_email_token_query(token),
         %UserToken{user_id: ^user_id} = user_token <- Repo.one(query) do
      {:ok, user_token}
    else
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Confirms an address from its emailed token.

  An address nobody holds is added to the user and the token is spent. One
  that belongs to another account returns `{:merge, other_user}` and leaves
  the token alone: it is spent by `McEmcomm.AccountMerge.merge/3` once the
  user has reviewed the merge.
  """
  @spec confirm_additional_email(User.t(), String.t()) ::
          {:ok, UserEmail.t()} | {:merge, User.t()} | {:error, :invalid}
  def confirm_additional_email(%User{} = user, token) do
    with {:ok, %UserToken{sent_to: email}} <- fetch_email_claim(user, token) do
      case get_user_by_email(email) do
        nil -> add_confirmed_email(user, email)
        %User{id: id} when id == user.id -> {:error, :invalid}
        %User{} = other -> {:merge, other}
      end
    end
  end

  defp add_confirmed_email(user, email) do
    Repo.transact(fn ->
      with {:ok, user_email} <-
             %UserEmail{user_id: user.id} |> UserEmail.changeset(%{email: email}) |> Repo.insert(),
           {_count, _result} <- delete_email_claims(user, email) do
        {:ok, user_email}
      else
        _ -> {:error, :invalid}
      end
    end)
  end

  @doc "Deletes the user's add-email tokens for the address, spent or superseded."
  @spec delete_email_claims(User.t(), String.t()) :: {non_neg_integer(), nil}
  def delete_email_claims(%User{id: user_id}, email) do
    Repo.delete_all(
      from t in UserToken,
        where: t.user_id == ^user_id and t.context == "add_email" and t.sent_to == ^email
    )
  end

  @doc """
  Removes one of the user's additional addresses. The primary address cannot
  be removed; another one has to be made primary first.
  """
  @spec remove_user_email(User.t(), integer() | nil) ::
          {:ok, UserEmail.t()} | {:error, :not_found}
  def remove_user_email(%User{} = user, id) do
    case get_user_email(user, id) do
      nil -> {:error, :not_found}
      user_email -> Repo.delete(user_email)
    end
  end

  @doc """
  Makes one of the user's additional addresses the primary one, where
  account mail is sent. The old primary address stays on the account as an
  additional address.
  """
  @spec make_email_primary(User.t(), integer() | nil) ::
          {:ok, User.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def make_email_primary(%User{} = user, id) do
    case get_user_email(user, id) do
      nil -> {:error, :not_found}
      user_email -> Repo.transact(fn -> swap_primary_email(user, user_email) end)
    end
  end

  defp get_user_email(user, id) when is_integer(id) do
    Repo.get_by(UserEmail, id: id, user_id: user.id)
  end

  defp get_user_email(_user, _id), do: nil

  defp swap_primary_email(user, user_email) do
    with {:ok, _user_email} <-
           user_email |> Ecto.Changeset.change(email: user.email) |> Repo.update() do
      user |> User.primary_email_changeset(user_email.email) |> Repo.update()
    end
  end

  # The address as stored on the account when `email` is one of the user's
  # own (addresses compare case-insensitively), otherwise nil.
  defp own_address(%User{} = user, email) do
    wanted = String.downcase(email)

    Enum.find([user.email | Enum.map(list_user_emails(user), & &1.email)], fn address ->
      String.downcase(address) == wanted
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `McEmcomm.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_password(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  When the account already has a password, `attrs` must carry a matching
  `current_password`; accounts without one set their first password freely.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{current_password: ..., password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{current_password: ..., password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user_password(User.t(), map()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t()}
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(User.t()) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  @spec get_user_by_session_token(binary()) :: {User.t(), DateTime.t()} | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  @spec get_user_by_magic_link_token(String.t()) :: User.t() | nil
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  @spec login_user_by_magic_link(String.t()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, :not_found}
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user |> User.confirm_changeset() |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_update_email_instructions(User.t(), String.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.

  ## Options

    * `:to` - the address the user asked to log in with. When it is one of
      their addresses the link is sent there; otherwise, and by default, it
      goes to the primary address.
  """
  @spec deliver_login_instructions(User.t(), (String.t() -> String.t()), keyword()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_login_instructions(%User{} = user, magic_link_url_fun, opts \\ [])
      when is_function(magic_link_url_fun, 1) do
    address = (opts[:to] && own_address(user, opts[:to])) || user.email
    {encoded_token, user_token} = UserToken.build_email_token(user, "login", address)
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token), address)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Two-factor authentication

  @doc """
  Returns true when the user has confirmed TOTP two-factor authentication.
  """
  @spec totp_enabled?(User.t() | nil) :: boolean()
  def totp_enabled?(%User{totp_confirmed_at: %DateTime{}}), do: true
  def totp_enabled?(_user), do: false

  @doc """
  Generates a raw TOTP secret for a new enrollment.

  The secret is not persisted; it lives only in the enrollment UI until the
  user confirms a code with `enable_totp/3`.
  """
  @spec generate_totp_secret() :: binary()
  def generate_totp_secret, do: NimbleTOTP.secret()

  @doc """
  Builds the `otpauth://` URI an authenticator app scans (usually as a QR code).
  """
  @spec totp_provisioning_uri(User.t(), binary()) :: String.t()
  def totp_provisioning_uri(%User{email: email}, secret) when is_binary(secret) do
    NimbleTOTP.otpauth_uri("#{@totp_issuer}:#{email}", secret, issuer: @totp_issuer)
  end

  @doc """
  Turns on TOTP for the user once they prove they hold the secret.

  Persists the secret, marks the enrollment code as used so it cannot be
  replayed at login, replaces any existing recovery codes, and returns the
  new plaintext recovery codes. They are shown to the user once and only
  their hashes are stored.

  ## Examples

      iex> enable_totp(user, secret, "123456")
      {:ok, {%User{}, ["abcd-efgh-ijkl-mnop", ...]}}

      iex> enable_totp(user, secret, "000000")
      {:error, :invalid_code}

  """
  @spec enable_totp(User.t(), binary(), String.t()) ::
          {:ok, {User.t(), [String.t()]}} | {:error, :invalid_code}
  def enable_totp(%User{} = user, secret, code) when is_binary(secret) and is_binary(code) do
    if NimbleTOTP.valid?(secret, code) do
      Repo.transact(fn -> persist_totp(user, secret) end)
    else
      {:error, :invalid_code}
    end
  end

  defp persist_totp(user, secret) do
    with {:ok, user} <- user |> User.totp_enable_changeset(secret) |> Repo.update() do
      {:ok, {user, replace_recovery_codes(user)}}
    end
  end

  @doc """
  Turns off TOTP for the user, forgetting the secret and deleting every
  recovery code. Idempotent.
  """
  @spec disable_totp(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def disable_totp(%User{} = user) do
    Repo.transact(fn ->
      with {:ok, user} <- user |> User.totp_disable_changeset() |> Repo.update() do
        Repo.delete_all(from(r in RecoveryCode, where: r.user_id == ^user.id))
        {:ok, user}
      end
    end)
  end

  @doc """
  Verifies a six-digit authenticator code for the user.

  A code is accepted at most once: the time window of the last successful
  verification is remembered and rejected if presented again.
  """
  @spec verify_totp(User.t(), String.t()) :: :ok | {:error, :invalid_code}
  def verify_totp(%User{totp_secret: secret} = user, code)
      when is_binary(secret) and is_binary(code) do
    if NimbleTOTP.valid?(secret, code, since: user.totp_last_used_at) do
      user
      |> User.totp_used_changeset(DateTime.utc_now())
      |> Repo.update!()

      :ok
    else
      {:error, :invalid_code}
    end
  end

  def verify_totp(_user, _code), do: {:error, :invalid_code}

  @doc """
  Consumes one of the user's unused recovery codes.

  Input is case-insensitive and dashes or spaces are ignored. The update is
  a single statement, so a code cannot be spent twice by concurrent requests.
  """
  @spec verify_recovery_code(User.t(), String.t()) :: :ok | {:error, :invalid_code}
  def verify_recovery_code(%User{id: user_id}, code) when is_binary(code) do
    hashed = RecoveryCode.hash(code)
    now = DateTime.utc_now(:second)

    query =
      from(r in RecoveryCode,
        where: r.user_id == ^user_id and r.hashed_code == ^hashed and is_nil(r.used_at)
      )

    case Repo.update_all(query, set: [used_at: now]) do
      {1, _} -> :ok
      _ -> {:error, :invalid_code}
    end
  end

  @doc """
  Verifies either second factor: six digits are treated as an authenticator
  code, anything else as a recovery code.
  """
  @spec verify_two_factor(User.t(), String.t()) ::
          {:ok, :totp} | {:ok, :recovery_code} | {:error, :invalid_code}
  def verify_two_factor(%User{} = user, code) when is_binary(code) do
    code = String.trim(code)

    if Regex.match?(@totp_code_format, code) do
      with :ok <- verify_totp(user, code), do: {:ok, :totp}
    else
      with :ok <- verify_recovery_code(user, code), do: {:ok, :recovery_code}
    end
  end

  @doc """
  Replaces the user's recovery codes with a fresh batch and returns the new
  plaintext codes. Only meaningful while TOTP is enabled.
  """
  @spec regenerate_recovery_codes(User.t()) :: {:ok, [String.t()]} | {:error, :totp_disabled}
  def regenerate_recovery_codes(%User{} = user) do
    if totp_enabled?(user) do
      Repo.transact(fn -> {:ok, replace_recovery_codes(user)} end)
    else
      {:error, :totp_disabled}
    end
  end

  @doc """
  Counts the user's recovery codes that have not been used yet.
  """
  @spec count_unused_recovery_codes(User.t()) :: non_neg_integer()
  def count_unused_recovery_codes(%User{id: user_id}) do
    Repo.aggregate(
      from(r in RecoveryCode, where: r.user_id == ^user_id and is_nil(r.used_at)),
      :count
    )
  end

  defp replace_recovery_codes(%User{id: user_id} = user) do
    Repo.delete_all(from(r in RecoveryCode, where: r.user_id == ^user_id))
    {codes, structs} = RecoveryCode.build_batch(user)
    Enum.each(structs, &Repo.insert!/1)
    codes
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end

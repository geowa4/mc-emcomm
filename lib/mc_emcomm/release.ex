defmodule McEmcomm.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :mc_emcomm

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Grants the admin flag to the user registered under `email`.

  Nothing in the deploy path seeds an administrator, so the first admin on a
  fresh production database is created by registering normally and then
  running this from the release:

      fly ssh console -C "/app/bin/mc_emcomm eval 'McEmcomm.Release.promote_admin(\"you@example.org\")'"

  Admin status does not require a member profile. Returns `{:ok, user}`, or
  `{:error, :not_found}` when no user has that email.
  """
  @spec promote_admin(String.t()) :: {:ok, McEmcomm.Accounts.User.t()} | {:error, :not_found}
  def promote_admin(email) when is_binary(email) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(McEmcomm.Repo, fn _repo -> do_promote_admin(email) end)

    result
  end

  defp do_promote_admin(email) do
    alias McEmcomm.Accounts

    case Accounts.get_user_by_email(email) do
      nil ->
        IO.puts("No user found with email #{email}")
        {:error, :not_found}

      user ->
        {:ok, user} = Accounts.promote_to_admin(user)
        IO.puts("#{user.email} is now an administrator")
        {:ok, user}
    end
  end

  @doc """
  Turns off two-factor authentication for the user registered under `email`.

  The escape hatch for a member who has lost both their authenticator and all
  of their recovery codes. Verify who you are talking to out of band before
  running it:

      fly ssh console -C "/app/bin/mc_emcomm eval 'McEmcomm.Release.disable_totp(\"you@example.org\")'"

  Idempotent. Forgets the TOTP secret and deletes every recovery code; existing
  sessions are left alone. Returns `{:ok, user}`, or `{:error, :not_found}`
  when no user has that email.
  """
  @spec disable_totp(String.t()) :: {:ok, McEmcomm.Accounts.User.t()} | {:error, :not_found}
  def disable_totp(email) when is_binary(email) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(McEmcomm.Repo, fn _repo -> do_disable_totp(email) end)

    result
  end

  defp do_disable_totp(email) do
    alias McEmcomm.Accounts

    case Accounts.get_user_by_email(email) do
      nil ->
        IO.puts("No user found with email #{email}")
        {:error, :not_found}

      user ->
        {:ok, user} = Accounts.disable_totp(user)
        IO.puts("Two-factor authentication disabled for #{user.email}")
        {:ok, user}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end

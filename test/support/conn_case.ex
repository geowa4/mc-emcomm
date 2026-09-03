defmodule McEmcommWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use McEmcommWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate
  use McEmcommWeb, :verified_routes

  import ExUnit.Assertions
  import Phoenix.ConnTest

  # For the helpers defined in this module's own body.
  @endpoint McEmcommWeb.Endpoint

  using do
    quote do
      # The default endpoint for testing
      @endpoint McEmcommWeb.Endpoint

      use McEmcommWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import PhoenixTest
      import McEmcommWeb.ConnCase
    end
  end

  setup tags do
    McEmcomm.DataCase.setup_sandbox(tags)
    {:ok, conn: build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = McEmcomm.AccountsFixtures.user_fixture()
    scope = McEmcomm.Accounts.Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Asserts that `conn` renders the signed-in navigation for `user`.

  Used after a login round-trip to prove the session actually took effect on a
  subsequent request, not just on the redirect.
  """
  def assert_logged_in_menu(conn, user) do
    response = conn |> get(~p"/") |> html_response(200)

    [email_local_part, _domain] = String.split(user.email, "@")
    assert response =~ email_local_part
    assert response =~ ~p"/users/settings"
    assert response =~ ~p"/users/log-out"
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = McEmcomm.Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  Parks a two-factor login for `user` in the `conn` session, as
  `McEmcommWeb.UserAuth.challenge_two_factor/4` would after a successful
  password or magic-link login.

  Options: `:remember_me` (`"true"` or nil), `:info` (the success flash),
  `:at` (unix seconds, to simulate an old challenge), `:attempts`.
  """
  def put_pending_two_factor(conn, user, opts \\ []) do
    pending =
      McEmcommWeb.UserAuth.build_pending_two_factor(
        user,
        %{"remember_me" => opts[:remember_me]},
        opts[:info] || "Welcome back!"
      )

    overrides =
      opts
      |> Keyword.take([:at, :attempts])
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

    Phoenix.ConnTest.init_test_session(conn, %{pending_two_factor: Map.merge(pending, overrides)})
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    McEmcomm.AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end

defmodule McEmcommWeb.UserLive.EmailClaimTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import McEmcomm.AccountsFixtures
  import McEmcomm.McEmcommFixtures

  alias McEmcomm.Accounts
  alias McEmcomm.Courses
  alias McEmcomm.Members

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "confirming a free address" do
    test "adds it and returns to the account page", %{conn: conn, user: user} do
      email = unique_user_email()
      token = email_claim_token(user, email)

      {:error, {:live_redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/users/settings/emails/#{token}")

      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "#{email} was added to your account."
      assert [%{email: ^email}] = Accounts.list_user_emails(user)
    end

    test "lands on the home page when the login is no longer recent", %{user: user} do
      token = email_claim_token(user, unique_user_email())

      conn =
        log_in_user(build_conn(), user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/users/settings/emails/#{token}")

      assert [_] = Accounts.list_user_emails(user)
    end

    test "rejects an invalid link", %{conn: conn, user: user} do
      {:error, {:live_redirect, %{flash: flash}}} =
        live(conn, ~p"/users/settings/emails/nonsense")

      assert %{"error" => "Email confirmation link is invalid or it has expired."} = flash
      assert Accounts.list_user_emails(user) == []
    end

    test "rejects a link opened from another account", %{user: user} do
      token = email_claim_token(user, unique_user_email())
      conn = log_in_user(build_conn(), user_fixture())

      {:error, {:live_redirect, %{flash: flash}}} =
        live(conn, ~p"/users/settings/emails/#{token}")

      assert %{"error" => _} = flash
      assert Accounts.list_user_emails(user) == []
    end

    test "requires a login", %{user: user} do
      token = email_claim_token(user, unique_user_email())

      assert {:error, {:redirect, %{to: path}}} =
               live(build_conn(), ~p"/users/settings/emails/#{token}")

      assert path == ~p"/users/log-in"
    end
  end

  describe "merge review" do
    test "explains the merge and offers the other profile's details", %{conn: conn} do
      mine = pending_member_fixture(%{name: "Pat Example"})
      theirs = member_fixture(%{name: "Patricia Example", call_sign: "W2PAT"})
      position = position_fixture(%{name: "Quartermaster"})
      {:ok, _} = Members.assign_position(theirs, position)
      {:ok, other} = Accounts.promote_to_admin(theirs.user)
      course = course_fixture(%{name: "IS-100"})
      {:ok, _} = Courses.add_member_course(%{member_id: theirs.id, course_id: course.id})

      token = email_claim_token(mine.user, other.email)

      {:ok, lv, _html} =
        conn |> log_in_user(mine.user) |> live(~p"/users/settings/emails/#{token}")

      assert has_element?(lv, "#merge-review")
      refute has_element?(lv, "#merge-blocked")
      assert has_element?(lv, "#merge-other-email", other.email)
      assert has_element?(lv, "#merge-gains-approved")
      assert has_element?(lv, "#merge-gains-positions", "Quartermaster")
      assert has_element?(lv, "#merge-gains-admin")
      refute has_element?(lv, "#merge-adopts-profile")

      assert has_element?(lv, "#merge-group-profile #merge-item-name", "Patricia Example")
      assert has_element?(lv, "#merge-item-name input:not([checked])")
      assert has_element?(lv, "#merge-item-call_sign input[checked]")
      assert has_element?(lv, "#merge-group-courses #merge-item-course-#{course.id}", "IS-100")
    end

    test "merges with the ticked details and disconnects the other account", %{conn: conn} do
      mine = member_fixture(%{name: "Pat Example"})
      theirs = member_fixture(%{name: "Patricia Example", call_sign: "W2PAT"})
      token = email_claim_token(mine.user, theirs.user.email)

      other_session = Accounts.generate_user_session_token(theirs.user)
      McEmcommWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(other_session)}")

      {:ok, lv, _html} =
        conn |> log_in_user(mine.user) |> live(~p"/users/settings/emails/#{token}")

      lv
      |> form("#merge-form", %{"merge" => %{"items" => ["name"]}})
      |> render_submit()

      {path, flash} = assert_redirect(lv)
      assert path == ~p"/"
      assert %{"info" => "The accounts were merged."} = flash

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

      merged = Members.get_member!(mine.id)
      assert merged.name == "Patricia Example"
      assert merged.call_sign == nil
      assert Members.get_member!(theirs.id).status == :inactive
      assert Accounts.get_user_by_email(theirs.user.email).id == mine.user.id
      refute Accounts.get_user_by_session_token(other_session)
    end

    test "merges with nothing ticked", %{conn: conn} do
      mine = member_fixture(%{name: "Pat Example"})
      theirs = member_fixture(%{name: "Patricia Example"})
      token = email_claim_token(mine.user, theirs.user.email)

      {:ok, lv, _html} =
        conn |> log_in_user(mine.user) |> live(~p"/users/settings/emails/#{token}")

      render_submit(lv, "merge", %{})
      assert_redirect(lv, ~p"/")

      assert Members.get_member!(mine.id).name == "Pat Example"
      assert Accounts.get_user!(theirs.user.id).deactivated_at
    end

    test "says when the other profile becomes the user's own", %{conn: conn, user: user} do
      theirs = member_fixture()
      token = email_claim_token(user, theirs.user.email)

      {:ok, lv, _html} = live(conn, ~p"/users/settings/emails/#{token}")

      assert has_element?(lv, "#merge-adopts-profile", "Approved")
      refute has_element?(lv, "#merge-group-profile")
    end

    test "says when there is nothing to choose", %{conn: conn} do
      mine = member_fixture(%{name: "Same Name"})
      theirs = member_fixture(%{name: "Same Name"})
      token = email_claim_token(mine.user, theirs.user.email)

      {:ok, lv, _html} =
        conn |> log_in_user(mine.user) |> live(~p"/users/settings/emails/#{token}")

      assert has_element?(lv, "#merge-no-items")
    end

    test "is refused for an account with two-factor authentication", %{conn: conn, user: user} do
      %{user: other} = user_with_totp_fixture()
      token = email_claim_token(user, other.email)

      {:ok, lv, _html} = live(conn, ~p"/users/settings/emails/#{token}")

      assert has_element?(lv, "#merge-blocked")
      refute has_element?(lv, "#merge-form")

      # A hand-built event gets no further.
      render_submit(lv, "merge", %{})
      assert has_element?(lv, "#merge-blocked")
      refute Accounts.get_user!(other.id).deactivated_at
    end

    test "reports a link that stopped being valid while the page was open", %{
      conn: conn,
      user: user
    } do
      other = user_fixture()
      extra = user_email_fixture(other)
      token = email_claim_token(user, extra.email)

      {:ok, lv, _html} = live(conn, ~p"/users/settings/emails/#{token}")
      {:ok, _} = Accounts.remove_user_email(other, extra.id)

      render_submit(lv, "merge", %{})

      {path, flash} = assert_redirect(lv)
      assert path == ~p"/"
      assert %{"error" => "Email confirmation link is invalid or it has expired."} = flash
      refute Accounts.get_user!(other.id).deactivated_at
    end
  end
end

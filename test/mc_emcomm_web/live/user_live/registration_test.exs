defmodule McEmcommWeb.UserLive.RegistrationTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import McEmcomm.AccountsFixtures

  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces"})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "emails the flagged position holders about the new member", %{conn: conn} do
      holder = McEmcommFixtures.member_fixture()
      flagged = McEmcommFixtures.position_fixture(%{notify_on_new_member: true})
      {:ok, _} = Members.assign_position(holder, flagged)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form",
          user: valid_user_attributes(email: email, name: "Newcomer", call_sign: "KD2XYZ")
        )

      {:ok, _lv, _html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      holder_email = holder.user.email

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "New member awaiting approval: Newcomer",
                        to: [{_, ^holder_email}],
                        text_body: body
                      }}

      assert body =~ "KD2XYZ"
      assert body =~ email
      assert body =~ "not\nconfirmed their email address yet"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "name" => "Test Member"}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end
end

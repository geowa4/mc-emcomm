defmodule McEmcommWeb.UserLive.TwoFactorTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import McEmcomm.AccountsFixtures

  alias McEmcomm.Accounts
  alias McEmcomm.Accounts.RecoveryCode

  describe "access" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/users/settings/two-factor")

      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings/two-factor")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "enrollment" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "starts in the off state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/two-factor")

      assert has_element?(lv, "#two-factor-status", "Off")
      assert has_element?(lv, "#two-factor-begin")
      refute has_element?(lv, "#two-factor-disable")
      refute has_element?(lv, "#two-factor-qr")
    end

    test "shows a QR code and manual key without persisting anything", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/two-factor")

      lv |> element("#two-factor-begin") |> render_click()

      assert has_element?(lv, "#two-factor-qr svg")
      assert has_element?(lv, "#two-factor-secret")
      assert has_element?(lv, "#two_factor_confirm_form")
      refute Accounts.get_user!(user.id).totp_secret
    end

    test "cancel returns to the off state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/two-factor")

      lv |> element("#two-factor-begin") |> render_click()
      lv |> element("#two-factor-cancel") |> render_click()

      refute has_element?(lv, "#two-factor-qr")
      assert has_element?(lv, "#two-factor-begin")
    end

    test "rejects a wrong code and stays in enrollment", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/two-factor")
      lv |> element("#two-factor-begin") |> render_click()

      html =
        lv
        |> form("#two_factor_confirm_form", totp: %{code: "000000"})
        |> render_submit()

      assert html =~ "is not valid"
      assert has_element?(lv, "#two_factor_confirm_form")
      refute Accounts.totp_enabled?(Accounts.get_user!(user.id))
    end

    test "a correct code turns TOTP on and reveals recovery codes once", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/two-factor")
      lv |> element("#two-factor-begin") |> render_click()

      secret = manual_key(lv)

      lv
      |> form("#two_factor_confirm_form", totp: %{code: totp_code(secret)})
      |> render_submit()

      assert Accounts.totp_enabled?(Accounts.get_user!(user.id))
      assert has_element?(lv, "#two-factor-status", "On")
      assert has_element?(lv, "#two-factor-recovery-codes")

      for index <- 0..(RecoveryCode.code_count() - 1) do
        assert has_element?(lv, "#recovery-code-#{index}")
      end

      lv |> element("#two-factor-recovery-codes-done") |> render_click()
      refute has_element?(lv, "#two-factor-recovery-codes")
      assert has_element?(lv, "#two-factor-disable")
    end
  end

  describe "when enabled" do
    setup %{conn: conn} do
      %{user: user} = fixture = user_with_totp_fixture()
      Map.put(fixture, :conn, log_in_user(conn, user))
    end

    test "shows the enabled controls", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/two-factor")

      assert has_element?(lv, "#two-factor-status", "On")
      assert has_element?(lv, "#two-factor-recovery-count", "8 of 8")
      assert has_element?(lv, "#two-factor-regenerate")
      assert has_element?(lv, "#two-factor-disable")
      refute has_element?(lv, "#two-factor-begin")
    end

    test "regenerates recovery codes and invalidates the old ones", %{
      conn: conn,
      user: user,
      recovery_codes: [old | _]
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/two-factor")

      lv |> element("#two-factor-regenerate") |> render_click()

      assert has_element?(lv, "#two-factor-recovery-codes")
      assert has_element?(lv, "#recovery-code-#{RecoveryCode.code_count() - 1}")
      assert {:error, :invalid_code} = Accounts.verify_recovery_code(user, old)
    end

    test "turns TOTP off", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/two-factor")

      lv |> element("#two-factor-disable") |> render_click()

      assert has_element?(lv, "#two-factor-status", "Off")
      assert has_element?(lv, "#two-factor-begin")
      refute Accounts.totp_enabled?(Accounts.get_user!(user.id))
    end
  end

  defp manual_key(lv) do
    lv
    |> element("#two-factor-secret")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
    |> Base.decode32!(padding: false)
  end
end

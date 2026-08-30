defmodule MyAppWeb.UserLive.LoginLocalMailTest do
  # Swaps the global mailer config, so it cannot share the VM with other tests.
  use MyAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original = Application.get_env(:my_app, MyApp.Mailer)

    Application.put_env(
      :my_app,
      MyApp.Mailer,
      Keyword.put(original, :adapter, Swoosh.Adapters.Local)
    )

    on_exit(fn -> Application.put_env(:my_app, MyApp.Mailer, original) end)
    :ok
  end

  test "points at the local mailbox when the local adapter is configured", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(lv, "#local-mail-notice")
    assert has_element?(lv, "#local-mail-notice a[href='/dev/mailbox']")
  end
end

defmodule MyApp.Accounts.UserNotifierTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias MyApp.Accounts.UserNotifier

  test "account emails are sent from the configured mail_from address" do
    user = %MyApp.Accounts.User{email: "person@example.com"}

    assert {:ok, email} = UserNotifier.deliver_login_instructions(user, "https://example.com/x")
    assert email.from == {"MyApp", Application.fetch_env!(:my_app, :mail_from)}
    assert_email_sent(email)
  end
end

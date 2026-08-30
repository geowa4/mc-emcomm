defmodule McEmcomm.Accounts.UserNotifierTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias McEmcomm.Accounts.UserNotifier

  test "account emails are sent from the configured mail_from address" do
    user = %McEmcomm.Accounts.User{email: "person@example.com"}

    assert {:ok, email} = UserNotifier.deliver_login_instructions(user, "https://example.com/x")

    assert email.from ==
             {"Monroe County ARES/RACES", Application.fetch_env!(:mc_emcomm, :mail_from)}

    assert_email_sent(email)
  end
end

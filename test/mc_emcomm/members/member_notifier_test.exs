defmodule McEmcomm.Members.MemberNotifierTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias McEmcomm.Accounts.User
  alias McEmcomm.Members.Member
  alias McEmcomm.Members.MemberNotifier

  @member %Member{name: "Pat Example", call_sign: "N0CALL"}
  @user %User{email: "pat@example.com"}

  test "sends one email per recipient from the configured mail_from address" do
    recipients = [%User{email: "secretary@example.com"}, %User{email: "ec@example.com"}]

    assert {:ok, [first, second]} =
             MemberNotifier.deliver_new_member_notice(@member, @user, recipients)

    assert first.to == [{"", "secretary@example.com"}]
    assert second.to == [{"", "ec@example.com"}]

    assert first.from ==
             {"Monroe County ARES/RACES", Application.fetch_env!(:mc_emcomm, :mail_from)}

    assert_email_sent(first)
    assert_email_sent(second)
  end

  test "the body identifies the member and links to the admin members page" do
    assert {:ok, [email]} =
             MemberNotifier.deliver_new_member_notice(@member, @user, [
               %User{email: "secretary@example.com"}
             ])

    assert email.subject == "New member awaiting approval: Pat Example"
    assert email.text_body =~ "Pat Example"
    assert email.text_body =~ "N0CALL"
    assert email.text_body =~ "pat@example.com"
    assert email.text_body =~ "/admin/members"
  end

  test "a missing call sign is spelled out rather than left blank" do
    assert {:ok, [email]} =
             MemberNotifier.deliver_new_member_notice(
               %Member{name: "No Sign", call_sign: nil},
               @user,
               [%User{email: "secretary@example.com"}]
             )

    assert email.text_body =~ "none given"
  end

  test "no recipients means no email" do
    assert {:ok, []} = MemberNotifier.deliver_new_member_notice(@member, @user, [])
    refute_email_sent()
  end
end

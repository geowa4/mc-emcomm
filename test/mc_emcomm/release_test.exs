defmodule McEmcomm.ReleaseTest do
  use McEmcomm.DataCase, async: true

  import ExUnit.CaptureIO
  import McEmcomm.AccountsFixtures

  alias McEmcomm.Accounts
  alias McEmcomm.Accounts.User
  alias McEmcomm.Release

  describe "promote_admin/1" do
    test "grants the admin flag to the user with that email" do
      user = user_fixture()

      {result, output} = with_io(fn -> Release.promote_admin(user.email) end)

      assert {:ok, %User{is_admin: true}} = result
      assert output =~ "is now an administrator"
      assert Accounts.get_user!(user.id).is_admin
    end

    test "reports an unknown email without raising" do
      {result, output} = with_io(fn -> Release.promote_admin("nobody@example.com") end)

      assert result == {:error, :not_found}
      assert output =~ "No user found"
    end
  end
end

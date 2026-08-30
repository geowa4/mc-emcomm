defmodule McEmcomm.ResendConfigTest do
  # Mutates application config, so it cannot run concurrently with other
  # Resend tests.
  use ExUnit.Case, async: false

  alias McEmcomm.Resend

  test "list_received/1 fails fast without an API key" do
    original = Application.get_env(:mc_emcomm, :resend_api_key)
    on_exit(fn -> Application.put_env(:mc_emcomm, :resend_api_key, original) end)

    Application.put_env(:mc_emcomm, :resend_api_key, nil)
    assert {:error, :missing_api_key} = Resend.list_received()
    assert {:error, :missing_api_key} = Resend.list_received_all()
  end
end

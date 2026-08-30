defmodule McEmcomm.Resend.Client do
  @moduledoc """
  Contract for a Resend Receiving API client.

  Consumers (e.g. `McEmcommWeb.InboxLive`) depend on this behaviour rather than
  on `McEmcomm.Resend` directly, so tests can swap in a Mox mock
  (`McEmcomm.ResendMock`, see `test/support/mocks.ex` and `:resend_client` in
  `config/test.exs`).
  """

  @callback list_received_all() :: {:ok, [McEmcomm.Resend.email()]} | {:error, term()}
end

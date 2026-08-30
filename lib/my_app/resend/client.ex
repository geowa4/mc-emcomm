defmodule MyApp.Resend.Client do
  @moduledoc """
  Contract for a Resend Receiving API client.

  Consumers (e.g. `MyAppWeb.InboxLive`) depend on this behaviour rather than
  on `MyApp.Resend` directly, so tests can swap in a Mox mock
  (`MyApp.ResendMock`, see `test/support/mocks.ex` and `:resend_client` in
  `config/test.exs`).
  """

  @callback list_received_all() :: {:ok, [MyApp.Resend.email()]} | {:error, term()}
end

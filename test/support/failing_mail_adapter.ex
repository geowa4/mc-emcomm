defmodule McEmcomm.FailingMailAdapter do
  @moduledoc """
  Swoosh adapter whose every delivery fails the way the Resend adapter does
  when the API rejects a request, for exercising the `{:error, reason}`
  branches of mail-sending call sites. Swap it into the `McEmcomm.Mailer`
  config in a synchronous test; the config is global.
  """
  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config) do
    {:error, {400, %{"message" => "API key is invalid", "name" => "validation_error"}}}
  end
end

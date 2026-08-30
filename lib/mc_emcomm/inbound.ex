defmodule McEmcomm.Inbound do
  @moduledoc """
  Inbound webhook processing and extension point. No email data is persisted.

  The webhook controller calls `record_event/2` (dedupe) and then
  `handle_event/1` asynchronously. Future processing (Receiving API fetches,
  agent workflows, ...) belongs here.
  """

  alias McEmcomm.Inbound.WebhookEvent
  alias McEmcomm.Repo

  @doc """
  Records a webhook delivery by its `svix-id`. Returns `{:error, :duplicate}`
  when the delivery has already been seen.
  """
  @spec record_event(String.t(), String.t() | nil) ::
          {:ok, WebhookEvent.t()} | {:error, :duplicate}
  def record_event(svix_id, event_type) do
    %WebhookEvent{}
    |> WebhookEvent.changeset(%{svix_id: svix_id, event_type: event_type})
    |> Repo.insert()
    |> case do
      {:ok, event} -> {:ok, event}
      {:error, _changeset} -> {:error, :duplicate}
    end
  end

  @doc "Called by the webhook controller after signature verification and dedupe."
  @spec handle_event(map()) :: :ok
  def handle_event(_event), do: :ok
end

defmodule MyApp.Inbound.WebhookEvent do
  @moduledoc """
  Dedupe record for inbound webhooks. Only the Svix delivery id and the event
  type are stored; email metadata is never persisted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "webhook_events" do
    field :svix_id, :string
    field :event_type, :string
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:svix_id, :event_type])
    |> validate_required([:svix_id])
    |> unique_constraint(:svix_id)
  end
end

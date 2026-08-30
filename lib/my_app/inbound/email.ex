defmodule MyApp.Inbound.Email do
  @moduledoc """
  Normalized inbound email metadata: the single shape shared by the webhook
  fan-out and the Receiving API backfill.

  Nothing is persisted. This struct exists so the two sources cannot drift
  apart — both build it through the constructors below, and `@enforce_keys`
  plus the typespec let the compiler and Dialyzer keep them in step.
  """

  alias MyApp.Inbound

  @enforce_keys [:id, :email_id, :from, :to, :subject, :received_at]
  defstruct [:id, :email_id, :from, :to, :subject, :received_at]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          email_id: String.t() | nil,
          from: String.t(),
          to: [String.t()],
          subject: String.t() | nil,
          received_at: String.t() | nil
        }

  @doc """
  Builds the struct from the `data` object of an `email.received` webhook,
  which identifies the email as `email_id`.
  """
  @spec from_webhook(map()) :: t()
  def from_webhook(data) when is_map(data), do: new(data["email_id"], data)

  @doc """
  Builds the struct from a received-email object returned by
  `GET /emails/receiving`, which identifies the email as `id`.
  """
  @spec from_api(MyApp.Resend.email()) :: t()
  def from_api(email) when is_map(email), do: new(email["id"], email)

  defp new(id, source) do
    %__MODULE__{
      id: id,
      email_id: id,
      from: Inbound.normalize(source["from"]),
      to: source["to"] || [],
      subject: source["subject"],
      received_at: source["created_at"]
    }
  end
end

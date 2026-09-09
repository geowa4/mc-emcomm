defmodule McEmcomm.Operations.OperationRsvp do
  @moduledoc """
  A member's stated intent to attend an operation. Distinct from
  `McEmcomm.Operations.OperationAttendance`, which records who actually
  showed up whether or not they responded beforehand.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type response :: :yes | :maybe | :no

  @responses ~w(yes maybe no)a
  @spec responses() :: [response()]
  def responses, do: @responses

  @note_max_length 500
  def note_max_length, do: @note_max_length

  schema "operation_rsvps" do
    field :response, Ecto.Enum, values: @responses
    field :note, :string
    field :responded_at, :utc_datetime_usec

    belongs_to :operation, McEmcomm.Operations.Operation
    belongs_to :member, McEmcomm.Members.Member

    timestamps(type: :utc_datetime)
  end

  @doc """
  The member-facing changeset: only the response and note are cast;
  `operation_id`, `member_id`, and `responded_at` are set by the context.
  """
  def changeset(rsvp, attrs) do
    rsvp
    |> cast(attrs, [:response, :note])
    |> update_change(:note, &blank_to_nil/1)
    |> validate_required([:response, :operation_id, :member_id, :responded_at])
    |> validate_length(:note, max: @note_max_length)
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:member_id)
    |> unique_constraint([:operation_id, :member_id])
  end

  defp blank_to_nil(note) when is_binary(note) do
    case String.trim(note) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(note), do: note
end
